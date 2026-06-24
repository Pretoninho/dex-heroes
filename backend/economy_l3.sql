-- ============================================================================
-- Dex Heroes — L3 : NPC market-maker (le marché vit tout seul)
-- À coller dans Supabase APRÈS economy.sql + economy_l2.sql
-- ============================================================================
-- Principe :
-- - Un NPC est un acteur (economy_actors type='npc') avec une policy (jsonb).
-- - Le market-maker poste EN PERMANENCE un buy sous le cours et un sell au-dessus
--   (un spread) → il garantit la liquidité. Sans joueurs, ses 2 ordres ne se
--   matchent pas entre eux (anti auto-match) → le ledger reste intact.
-- - Un tick pg_cron (à la minute) annule ses vieux ordres et en repose des frais.
-- - La policy décrit tout : { "role":"market_maker", "spread":0.04, "depth":50,
--   "anchor":100 }  (anchor = cours de référence tant qu'il n'y a aucun trade).
-- ============================================================================

-- 1) Moteur de matching v2 (anti auto-match correct) -------------------------
-- Remplace la version L2 : au lieu de s'arrêter sur un auto-match, on ne
-- considère que les paires buy/sell d'acteurs DIFFÉRENTS qui se croisent.
create or replace function public.economy_match_orders()
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_pair record;
  v_system_id uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_qty numeric;
  v_exec_price numeric;
  v_cash numeric;
  v_refund numeric;
  v_tx_id uuid;
  v_matches integer := 0;
begin
  loop
    -- Meilleure paire croisante d'acteurs DIFFÉRENTS :
    -- meilleur acheteur (prix max, ancienneté) vs meilleur vendeur (prix min)
    select
      b.id as buy_id, b.actor_id as buyer, b.price as buy_price, b.gems_remaining as buy_rem,
      s.id as sell_id, s.actor_id as seller, s.price as sell_price, s.gems_remaining as sell_rem
    into v_pair
    from public.economy_orders b
    join public.economy_orders s
      on s.side = 'sell' and s.status = 'open' and s.gems_remaining > 0
     and s.actor_id <> b.actor_id
     and s.price <= b.price
    where b.side = 'buy' and b.status = 'open' and b.gems_remaining > 0
    order by b.price desc, s.price asc, b.created_at asc, s.created_at asc
    limit 1;

    exit when not found;

    v_qty := least(v_pair.buy_rem, v_pair.sell_rem);
    v_exec_price := v_pair.sell_price;       -- le maker (sell, le plus ancien/bas) fait le prix
    v_cash := v_qty * v_exec_price;
    v_tx_id := gen_random_uuid();

    -- Règlement depuis le séquestre (SYSTÈME) : gems -> acheteur, cash -> vendeur
    perform public.economy_post_tx(v_tx_id, jsonb_build_array(
      jsonb_build_object('actor_id', v_system_id,   'resource_id', 'gems', 'delta', -v_qty, 'kind', 'trade', 'metadata', jsonb_build_object('price', v_exec_price)),
      jsonb_build_object('actor_id', v_pair.buyer,  'resource_id', 'gems', 'delta',  v_qty, 'kind', 'trade', 'metadata', jsonb_build_object('price', v_exec_price)),
      jsonb_build_object('actor_id', v_system_id,   'resource_id', 'cash', 'delta', -v_cash, 'kind', 'trade', 'metadata', jsonb_build_object('price', v_exec_price)),
      jsonb_build_object('actor_id', v_pair.seller, 'resource_id', 'cash', 'delta',  v_cash, 'kind', 'trade', 'metadata', jsonb_build_object('price', v_exec_price))
    ));

    -- Rendre à l'acheteur sa sur-réservation (il avait séquestré buy_price)
    if v_pair.buy_price > v_exec_price then
      v_refund := v_qty * (v_pair.buy_price - v_exec_price);
      perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
        jsonb_build_object('actor_id', v_system_id,  'resource_id', 'cash', 'delta', -v_refund, 'kind', 'refund'),
        jsonb_build_object('actor_id', v_pair.buyer, 'resource_id', 'cash', 'delta',  v_refund, 'kind', 'refund')
      ));
    end if;

    -- Fait de trade
    insert into public.economy_trades (tx_id, buy_order, sell_order, buyer_id, seller_id, gems, price, cash)
      values (v_tx_id, v_pair.buy_id, v_pair.sell_id, v_pair.buyer, v_pair.seller, v_qty, v_exec_price, v_cash);

    -- Décrément + clôture
    update public.economy_orders set gems_remaining = gems_remaining - v_qty,
      status = case when gems_remaining - v_qty <= 0 then 'filled' else 'open' end
      where id = v_pair.buy_id;
    update public.economy_orders set gems_remaining = gems_remaining - v_qty,
      status = case when gems_remaining - v_qty <= 0 then 'filled' else 'open' end
      where id = v_pair.sell_id;

    v_matches := v_matches + 1;
    exit when v_matches > 500;   -- garde-fou anti-boucle
  end loop;

  if v_matches > 0 then perform public.economy_refresh_price(); end if;
  return v_matches;
end; $$;

grant execute on function public.economy_match_orders() to authenticated;

-- 2) Helpers internes (agissent pour un acteur donné, sans auth) -------------

-- Poster un ordre AU NOM d'un acteur (NPC). Escrow + insert. Retourne l'ordre
-- ou null si l'escrow échoue (fonds insuffisants) → le tick saute cette face.
create or replace function public.economy_place_order_as(
  p_actor_id uuid, p_side text, p_gems numeric, p_price numeric
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_system_id uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_cash numeric := p_gems * p_price;
  v_res jsonb;
  v_order_id uuid;
begin
  if p_side not in ('buy','sell') or p_gems <= 0 or p_price <= 0 then return null; end if;

  if p_side = 'buy' then
    v_res := public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id', p_actor_id,  'resource_id', 'cash', 'delta', -v_cash, 'kind', 'escrow'),
      jsonb_build_object('actor_id', v_system_id, 'resource_id', 'cash', 'delta',  v_cash, 'kind', 'escrow')
    ));
  else
    v_res := public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id', p_actor_id,  'resource_id', 'gems', 'delta', -p_gems, 'kind', 'escrow'),
      jsonb_build_object('actor_id', v_system_id, 'resource_id', 'gems', 'delta',  p_gems, 'kind', 'escrow')
    ));
  end if;

  if (v_res->>'success')::boolean is not true then return null; end if;  -- fonds insuffisants → on saute

  insert into public.economy_orders (actor_id, side, gems, price, gems_remaining)
    values (p_actor_id, p_side, p_gems, p_price, p_gems)
    returning id into v_order_id;
  return v_order_id;
end; $$;

-- Annuler TOUS les ordres ouverts d'un acteur (rend le séquestre)
create or replace function public.economy_cancel_all_orders(p_actor_id uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_system_id uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_o public.economy_orders;
  v_refund numeric;
  v_n integer := 0;
begin
  for v_o in select * from public.economy_orders
    where actor_id = p_actor_id and status = 'open' for update
  loop
    if v_o.side = 'buy' then
      v_refund := v_o.gems_remaining * v_o.price;
      perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
        jsonb_build_object('actor_id', v_system_id, 'resource_id', 'cash', 'delta', -v_refund, 'kind', 'unescrow'),
        jsonb_build_object('actor_id', p_actor_id,  'resource_id', 'cash', 'delta',  v_refund, 'kind', 'unescrow')
      ));
    else
      perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
        jsonb_build_object('actor_id', v_system_id, 'resource_id', 'gems', 'delta', -v_o.gems_remaining, 'kind', 'unescrow'),
        jsonb_build_object('actor_id', p_actor_id,  'resource_id', 'gems', 'delta',  v_o.gems_remaining, 'kind', 'unescrow')
      ));
    end if;
    update public.economy_orders set status = 'cancelled' where id = v_o.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end; $$;

-- 3) Créer / amorcer le NPC market-maker -------------------------------------
-- Idempotent : ne crée qu'une fois, et le dote en cash + gems (faucet SYSTÈME).
create or replace function public.economy_ensure_market_maker()
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_mm uuid;
  v_seed_gems numeric := 1e6;     -- inventaire initial
  v_seed_cash numeric := 1e9;
  v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
begin
  select id into v_mm from public.economy_actors
    where type = 'npc' and policy->>'role' = 'market_maker' limit 1;

  if v_mm is null then
    insert into public.economy_actors (type, name, policy)
      values ('npc', 'Teneur de marché', jsonb_build_object(
        'role', 'market_maker', 'spread', 0.04, 'depth', 50, 'anchor', 100
      ))
      returning id into v_mm;

    -- Dotation initiale (faucet)
    perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id', v_sys, 'resource_id', 'gems', 'delta', -v_seed_gems, 'kind', 'production'),
      jsonb_build_object('actor_id', v_mm,  'resource_id', 'gems', 'delta',  v_seed_gems, 'kind', 'production')
    ));
    perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id', v_sys, 'resource_id', 'cash', 'delta', -v_seed_cash, 'kind', 'production'),
      jsonb_build_object('actor_id', v_mm,  'resource_id', 'cash', 'delta',  v_seed_cash, 'kind', 'production')
    ));
  end if;

  return v_mm;
end; $$;

-- 4) Le tick : fait respirer tous les NPC ------------------------------------
create or replace function public.economy_tick_npcs()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_npc public.economy_actors;
  v_ref numeric;
  v_spread numeric;
  v_depth numeric;
  v_anchor numeric;
  v_buy_price numeric;
  v_sell_price numeric;
  v_index_price numeric;
  v_count integer := 0;
begin
  -- S'assurer que le market-maker existe
  perform public.economy_ensure_market_maker();

  -- Cours de référence courant
  select price into v_index_price from public.economy_price_index where id = 'gems_cash';

  for v_npc in select * from public.economy_actors where type = 'npc' loop
    if v_npc.policy->>'role' = 'market_maker' then
      v_spread := coalesce((v_npc.policy->>'spread')::numeric, 0.04);
      v_depth  := coalesce((v_npc.policy->>'depth')::numeric, 50);
      v_anchor := coalesce((v_npc.policy->>'anchor')::numeric, 100);

      -- Référence : le cours s'il existe (>0), sinon l'ancre de la policy
      v_ref := case when coalesce(v_index_price,0) > 0 then v_index_price else v_anchor end;

      v_buy_price  := round(v_ref * (1 - v_spread), 4);
      v_sell_price := round(v_ref * (1 + v_spread), 4);

      -- Reposer des ordres frais : annuler les anciens, poster buy + sell
      perform public.economy_cancel_all_orders(v_npc.id);
      perform public.economy_place_order_as(v_npc.id, 'buy',  v_depth, v_buy_price);
      perform public.economy_place_order_as(v_npc.id, 'sell', v_depth, v_sell_price);
      v_count := v_count + 1;
    end if;
  end loop;

  -- Matcher (avec d'éventuels ordres de joueurs déjà au carnet)
  perform public.economy_match_orders();

  return jsonb_build_object('npcs_ticked', v_count, 'ref_price', v_ref);
end; $$;

grant execute on function public.economy_tick_npcs() to authenticated;

-- 5) Planifier le tick (pg_cron) ---------------------------------------------
-- ⚠️ Active d'abord l'extension : Dashboard → Database → Extensions → "pg_cron".
-- Puis dé-commente et exécute ces 2 lignes (à faire UNE fois) :
--
--   create extension if not exists pg_cron;
--   select cron.schedule('npc-tick', '* * * * *', $$ select public.economy_tick_npcs(); $$);
--
-- Pour voir / supprimer le job :
--   select * from cron.job;
--   select cron.unschedule('npc-tick');
