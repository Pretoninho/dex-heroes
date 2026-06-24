-- ============================================================================
-- Dex Heroes — Bloc 2 : Frais de l'Exchange (maker/taker + retrait)
-- À coller APRÈS economy.sql + l2 + l3 + l4 + economy_market_api.sql
-- ============================================================================
-- Principe : un frais = la part d'un règlement qui RESTE chez SYSTÈME au lieu
-- d'aller au bénéficiaire. C'est un SINK pur → conservation préservée (chaque
-- ressource somme toujours à 0 dans la tx). Taux dans economy_config (tunables).
--   maker  = ordre qui attendait au carnet (apporte la liquidité) → frais réduit
--   taker  = ordre qui croise le carnet (retire la liquidité)     → frais plein
-- ============================================================================

-- 1) Config des frais (tunable sans code) ------------------------------------
insert into public.economy_config (key, value) values
  ('fees', jsonb_build_object(
    'maker', 0.001,     -- 0,10 % pour le maker
    'taker', 0.002,     -- 0,20 % pour le taker
    'withdraw', 0.005   -- 0,50 % sur les retraits marché → jeu
  ))
on conflict (key) do nothing;

-- Colonnes de traçabilité des frais sur les trades (analytics)
alter table public.economy_trades add column if not exists fee_gems numeric not null default 0;
alter table public.economy_trades add column if not exists fee_cash numeric not null default 0;

-- 2) Moteur de matching AVEC frais maker/taker -------------------------------
create or replace function public.economy_match_orders()
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_pair record;
  v_system_id uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_qty numeric; v_exec_price numeric; v_cash numeric; v_refund numeric;
  v_tx_id uuid; v_matches integer := 0;
  v_cfg jsonb; v_maker numeric; v_taker numeric;
  v_taker_is_buyer boolean; v_buyer_fee numeric; v_seller_fee numeric;
  v_buyer_gems numeric; v_seller_cash numeric; v_fee_gems numeric; v_fee_cash numeric;
begin
  select value into v_cfg from public.economy_config where key = 'fees';
  v_maker := coalesce((v_cfg->>'maker')::numeric, 0.001);
  v_taker := coalesce((v_cfg->>'taker')::numeric, 0.002);

  loop
    select
      b.id as buy_id, b.actor_id as buyer, b.price as buy_price, b.gems_remaining as buy_rem, b.created_at as buy_at,
      s.id as sell_id, s.actor_id as seller, s.price as sell_price, s.gems_remaining as sell_rem, s.created_at as sell_at
    into v_pair
    from public.economy_orders b
    join public.economy_orders s
      on s.side = 'sell' and s.status = 'open' and s.gems_remaining > 0
     and s.actor_id <> b.actor_id and s.price <= b.price
    where b.side = 'buy' and b.status = 'open' and b.gems_remaining > 0
    order by b.price desc, s.price asc, b.created_at asc, s.created_at asc
    limit 1;

    exit when not found;

    v_qty := least(v_pair.buy_rem, v_pair.sell_rem);
    v_exec_price := v_pair.sell_price;
    v_cash := v_qty * v_exec_price;
    v_tx_id := gen_random_uuid();

    -- Taker = l'ordre arrivé en DERNIER (created_at le plus récent).
    v_taker_is_buyer := v_pair.buy_at > v_pair.sell_at;
    v_buyer_fee  := case when v_taker_is_buyer then v_taker else v_maker end;  -- sur les gems reçus
    v_seller_fee := case when v_taker_is_buyer then v_maker else v_taker end;  -- sur le cash reçu

    v_buyer_gems := v_qty  * (1 - v_buyer_fee);    -- gems nets pour l'acheteur
    v_seller_cash := v_cash * (1 - v_seller_fee);  -- cash net pour le vendeur
    v_fee_gems := v_qty  - v_buyer_gems;           -- reste chez SYSTÈME (sink)
    v_fee_cash := v_cash - v_seller_cash;

    -- Règlement net : SYSTÈME paie (1 - frais) de chaque jambe, garde le frais.
    perform public.economy_post_tx(v_tx_id, jsonb_build_array(
      jsonb_build_object('actor_id', v_system_id,   'resource_id', 'gems', 'delta', -v_buyer_gems, 'kind', 'trade', 'metadata', jsonb_build_object('price', v_exec_price)),
      jsonb_build_object('actor_id', v_pair.buyer,  'resource_id', 'gems', 'delta',  v_buyer_gems, 'kind', 'trade', 'metadata', jsonb_build_object('price', v_exec_price, 'fee', v_fee_gems)),
      jsonb_build_object('actor_id', v_system_id,   'resource_id', 'cash', 'delta', -v_seller_cash, 'kind', 'trade', 'metadata', jsonb_build_object('price', v_exec_price)),
      jsonb_build_object('actor_id', v_pair.seller, 'resource_id', 'cash', 'delta',  v_seller_cash, 'kind', 'trade', 'metadata', jsonb_build_object('price', v_exec_price, 'fee', v_fee_cash))
    ));

    -- Rendre à l'acheteur sa sur-réservation (séquestre au buy_price).
    if v_pair.buy_price > v_exec_price then
      v_refund := v_qty * (v_pair.buy_price - v_exec_price);
      perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
        jsonb_build_object('actor_id', v_system_id,  'resource_id', 'cash', 'delta', -v_refund, 'kind', 'refund'),
        jsonb_build_object('actor_id', v_pair.buyer, 'resource_id', 'cash', 'delta',  v_refund, 'kind', 'refund')
      ));
    end if;

    insert into public.economy_trades (tx_id, buy_order, sell_order, buyer_id, seller_id, gems, price, cash, fee_gems, fee_cash)
      values (v_tx_id, v_pair.buy_id, v_pair.sell_id, v_pair.buyer, v_pair.seller, v_qty, v_exec_price, v_cash, v_fee_gems, v_fee_cash);

    update public.economy_orders set gems_remaining = gems_remaining - v_qty,
      status = case when gems_remaining - v_qty <= 0 then 'filled' else 'open' end where id = v_pair.buy_id;
    update public.economy_orders set gems_remaining = gems_remaining - v_qty,
      status = case when gems_remaining - v_qty <= 0 then 'filled' else 'open' end where id = v_pair.sell_id;

    v_matches := v_matches + 1;
    exit when v_matches > 500;
  end loop;

  if v_matches > 0 then perform public.economy_refresh_price(); end if;
  return v_matches;
end; $$;
grant execute on function public.economy_match_orders() to authenticated;

-- 3) Retrait AVEC frais ------------------------------------------------------
-- Le solde marché baisse de w (intégralement vers SYSTÈME), mais le JEU n'est
-- recrédité que du NET = w * (1 - frais). Le client lit net_gems/net_cash.
create or replace function public.economy_withdraw(w_gems numeric, w_cash numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid; v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_entries jsonb := '[]'::jsonb; v_res jsonb; v_cfg jsonb; v_fee numeric;
  v_net_gems numeric; v_net_cash numeric;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  w_gems := coalesce(w_gems, 0); w_cash := coalesce(w_cash, 0);
  if w_gems < 0 or w_cash < 0 then raise exception 'negative amount'; end if;
  if w_gems = 0 and w_cash = 0 then return jsonb_build_object('success', false, 'error', 'empty'); end if;

  select value into v_cfg from public.economy_config where key = 'fees';
  v_fee := coalesce((v_cfg->>'withdraw')::numeric, 0.005);

  v_actor := public.economy_ensure_player();
  if w_gems > 0 then
    v_entries := v_entries
      || jsonb_build_object('actor_id', v_actor, 'resource_id', 'gems', 'delta', -w_gems, 'kind', 'withdraw')
      || jsonb_build_object('actor_id', v_sys,   'resource_id', 'gems', 'delta',  w_gems, 'kind', 'withdraw');
  end if;
  if w_cash > 0 then
    v_entries := v_entries
      || jsonb_build_object('actor_id', v_actor, 'resource_id', 'cash', 'delta', -w_cash, 'kind', 'withdraw')
      || jsonb_build_object('actor_id', v_sys,   'resource_id', 'cash', 'delta',  w_cash, 'kind', 'withdraw');
  end if;

  v_res := public.economy_post_tx(gen_random_uuid(), v_entries);  -- refuse si solde insuffisant
  if (v_res->>'success')::boolean is not true then return v_res; end if;

  v_net_gems := floor(w_gems * (1 - v_fee));
  v_net_cash := floor(w_cash * (1 - v_fee));
  return jsonb_build_object('success', true, 'net_gems', v_net_gems, 'net_cash', v_net_cash,
    'fee_gems', w_gems - v_net_gems, 'fee_cash', w_cash - v_net_cash);
end; $$;
grant execute on function public.economy_withdraw(numeric, numeric) to authenticated;

-- 4) Exposer les frais au client (lecture publique) --------------------------
create or replace function public.economy_get_fees()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  select value into v from public.economy_config where key = 'fees';
  return coalesce(v, jsonb_build_object('maker',0.001,'taker',0.002,'withdraw',0.005));
end; $$;
grant execute on function public.economy_get_fees() to authenticated, anon;
