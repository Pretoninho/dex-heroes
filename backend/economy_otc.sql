-- ============================================================================
-- Dex Heroes — Tier OTC (desk 🐋 Hedge Fund) : venue séparée du retail
-- À coller APRÈS economy.sql + l2 + l3 + l4 + market_api + fees + market_order
--   + l3b + economy_retail.sql   (DERNIER fichier de la chaîne économie)
-- ============================================================================
-- On ajoute une DIMENSION `venue` au moteur existant ('retail' par défaut → 0
-- régression). Le matching est CLOISONNÉ par venue : un ordre retail ne croise
-- JAMAIS un ordre OTC. Deux cours indépendants (economy_price_index : 'gems_cash'
-- retail, 'gems_cash_otc' OTC) → un ÉCART émergent retail↔OTC = terrain
-- d'arbitrage pour le joueur. L'OTC : book MINCE, gros ordres, frais TAKER 1,0 %,
-- impact de prix réel. Un NPC « garde-fou » ne recolle l'écart qu'au-delà d'un
-- seuil (laisse la bande de profit au joueur). Conservation préservée partout
-- (tout passe par economy_post_tx → chaque ressource somme à 0).
-- ============================================================================

-- 1) Dimension venue sur le carnet + les trades ------------------------------
alter table public.economy_orders add column if not exists venue text not null default 'retail';
alter table public.economy_orders drop constraint if exists economy_orders_venue_chk;
alter table public.economy_orders add constraint economy_orders_venue_chk check (venue in ('retail','otc'));

alter table public.economy_trades add column if not exists venue text not null default 'retail';

create index if not exists idx_orders_venue_match on public.economy_orders (venue, side, status, price);
create index if not exists idx_trades_venue_time on public.economy_trades (venue, executed_at desc);

-- Cours OTC (ligne dédiée dans l'index de prix) — amorcé à 0 (le tick le remplit)
insert into public.economy_price_index (id, price) values ('gems_cash_otc', 0)
  on conflict (id) do nothing;

-- 2) Config OTC (frais élevés + seuil d'arbitrage + taille mini) --------------
insert into public.economy_config (key, value) values
  ('fees_otc', jsonb_build_object(
    'maker', 0.002,   -- 0,20 % maker OTC
    'taker', 0.010    -- 1,00 % taker OTC (5× le retail) — friction assumée
  )),
  ('otc', jsonb_build_object(
    'min_gems_per_order', 200,   -- gros ordres : taille minimale côté joueur
    'arb_threshold', 0.05,       -- le garde-fou n'agit qu'au-delà de 5 % d'écart
    'arb_size', 40               -- taille de l'intervention du garde-fou
  ))
on conflict (key) do nothing;

-- Helper : clé d'index de prix selon la venue
create or replace function public.economy_price_pk(p_venue text)
returns text language sql immutable as $$
  select case when p_venue = 'otc' then 'gems_cash_otc' else 'gems_cash' end;
$$;

-- 3) Rafraîchir le cours d'UNE venue -----------------------------------------
create or replace function public.economy_refresh_price_v(p_venue text)
returns numeric language plpgsql security definer set search_path = public as $$
declare v_n int := 20; v_price numeric; v_volume numeric; v_count int; v_pk text;
begin
  v_pk := public.economy_price_pk(p_venue);
  select coalesce(sum(price*gems)/nullif(sum(gems),0),0), coalesce(sum(gems),0), count(*)
    into v_price, v_volume, v_count
  from (select price, gems from public.economy_trades
        where venue = p_venue order by executed_at desc limit v_n) recent;
  update public.economy_price_index
    set price=v_price, volume_recent=v_volume, trades_count=v_count, updated_at=now()
    where id = v_pk;
  return v_price;
end; $$;
grant execute on function public.economy_refresh_price_v(text) to authenticated;

-- economy_refresh_price() = retail (rétro-compat) — DÉSORMAIS filtré venue='retail'
create or replace function public.economy_refresh_price()
returns numeric language plpgsql security definer set search_path = public as $$
begin return public.economy_refresh_price_v('retail'); end; $$;
grant execute on function public.economy_refresh_price() to authenticated;

-- 4) Matching CLOISONNÉ par venue (frais selon la venue) ----------------------
create or replace function public.economy_match_orders_v(p_venue text)
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
  select value into v_cfg from public.economy_config
    where key = case when p_venue='otc' then 'fees_otc' else 'fees' end;
  v_maker := coalesce((v_cfg->>'maker')::numeric, 0.001);
  v_taker := coalesce((v_cfg->>'taker')::numeric, 0.002);

  loop
    select
      b.id as buy_id, b.actor_id as buyer, b.price as buy_price, b.gems_remaining as buy_rem, b.created_at as buy_at,
      s.id as sell_id, s.actor_id as seller, s.price as sell_price, s.gems_remaining as sell_rem, s.created_at as sell_at
    into v_pair
    from public.economy_orders b
    join public.economy_orders s
      on s.side='sell' and s.status='open' and s.gems_remaining>0 and s.venue=p_venue
     and s.actor_id <> b.actor_id and s.price <= b.price
    where b.side='buy' and b.status='open' and b.gems_remaining>0 and b.venue=p_venue
    order by b.price desc, s.price asc, b.created_at asc, s.created_at asc
    limit 1;

    exit when not found;

    v_qty := least(v_pair.buy_rem, v_pair.sell_rem);
    v_exec_price := v_pair.sell_price;
    v_cash := v_qty * v_exec_price;
    v_tx_id := gen_random_uuid();

    v_taker_is_buyer := v_pair.buy_at > v_pair.sell_at;
    v_buyer_fee  := case when v_taker_is_buyer then v_taker else v_maker end;
    v_seller_fee := case when v_taker_is_buyer then v_maker else v_taker end;

    v_buyer_gems  := v_qty  * (1 - v_buyer_fee);
    v_seller_cash := v_cash * (1 - v_seller_fee);
    v_fee_gems := v_qty  - v_buyer_gems;
    v_fee_cash := v_cash - v_seller_cash;

    perform public.economy_post_tx(v_tx_id, jsonb_build_array(
      jsonb_build_object('actor_id', v_system_id,   'resource_id', 'gems', 'delta', -v_buyer_gems, 'kind', 'trade', 'metadata', jsonb_build_object('price', v_exec_price)),
      jsonb_build_object('actor_id', v_pair.buyer,  'resource_id', 'gems', 'delta',  v_buyer_gems, 'kind', 'trade', 'metadata', jsonb_build_object('price', v_exec_price, 'fee', v_fee_gems)),
      jsonb_build_object('actor_id', v_system_id,   'resource_id', 'cash', 'delta', -v_seller_cash, 'kind', 'trade', 'metadata', jsonb_build_object('price', v_exec_price)),
      jsonb_build_object('actor_id', v_pair.seller, 'resource_id', 'cash', 'delta',  v_seller_cash, 'kind', 'trade', 'metadata', jsonb_build_object('price', v_exec_price, 'fee', v_fee_cash))
    ));

    if v_pair.buy_price > v_exec_price then
      v_refund := v_qty * (v_pair.buy_price - v_exec_price);
      perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
        jsonb_build_object('actor_id', v_system_id,  'resource_id', 'cash', 'delta', -v_refund, 'kind', 'refund'),
        jsonb_build_object('actor_id', v_pair.buyer, 'resource_id', 'cash', 'delta',  v_refund, 'kind', 'refund')
      ));
    end if;

    insert into public.economy_trades (tx_id, buy_order, sell_order, buyer_id, seller_id, gems, price, cash, fee_gems, fee_cash, venue)
      values (v_tx_id, v_pair.buy_id, v_pair.sell_id, v_pair.buyer, v_pair.seller, v_qty, v_exec_price, v_cash, v_fee_gems, v_fee_cash, p_venue);

    update public.economy_orders set gems_remaining = gems_remaining - v_qty,
      status = case when gems_remaining - v_qty <= 0 then 'filled' else 'open' end where id = v_pair.buy_id;
    update public.economy_orders set gems_remaining = gems_remaining - v_qty,
      status = case when gems_remaining - v_qty <= 0 then 'filled' else 'open' end where id = v_pair.sell_id;

    v_matches := v_matches + 1;
    exit when v_matches > 500;
  end loop;

  if v_matches > 0 then perform public.economy_refresh_price_v(p_venue); end if;
  return v_matches;
end; $$;
grant execute on function public.economy_match_orders_v(text) to authenticated;

-- economy_match_orders() = retail (rétro-compat, appelé par le tick + place_order)
create or replace function public.economy_match_orders()
returns integer language plpgsql security definer set search_path = public as $$
begin return public.economy_match_orders_v('retail'); end; $$;
grant execute on function public.economy_match_orders() to authenticated;

-- 5) Ordre Market interne, venue-aware (le coeur) ----------------------------
-- L'impl complète vit dans la version 4-args. La 3-args (retail) délègue → 0
-- régression pour economy_market_order et economy_retail_buy_gems.
create or replace function public.economy_market_order_as(p_actor uuid, p_side text, p_gems numeric, p_venue text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_cfg jsonb; v_maker numeric; v_taker numeric;
  v_remaining numeric; v_filled numeric := 0; v_spent numeric := 0; v_recv numeric := 0;
  v_opp record; v_fill numeric; v_price numeric; v_cash numeric;
  v_bal numeric; v_buyer_gems numeric; v_seller_cash numeric; v_tx uuid; v_guard int := 0;
begin
  if p_side not in ('buy','sell') then return jsonb_build_object('success',false,'error','invalid side'); end if;
  if p_gems <= 0 then return jsonb_build_object('success',false,'error','invalid amount'); end if;

  select value into v_cfg from public.economy_config
    where key = case when p_venue='otc' then 'fees_otc' else 'fees' end;
  v_maker := coalesce((v_cfg->>'maker')::numeric, 0.001);
  v_taker := coalesce((v_cfg->>'taker')::numeric, 0.002);
  v_remaining := p_gems;

  loop
    v_guard := v_guard + 1; exit when v_guard > 500;
    if p_side = 'buy' then
      select * into v_opp from public.economy_orders
        where side='sell' and status='open' and gems_remaining>0 and actor_id<>p_actor and venue=p_venue
        order by price asc, created_at asc limit 1;
    else
      select * into v_opp from public.economy_orders
        where side='buy' and status='open' and gems_remaining>0 and actor_id<>p_actor and venue=p_venue
        order by price desc, created_at asc limit 1;
    end if;
    exit when not found;

    v_price := v_opp.price;
    v_fill := least(v_remaining, v_opp.gems_remaining);

    if p_side = 'buy' then
      select balance into v_bal from public.economy_balances where actor_id=p_actor and resource_id='cash';
      v_bal := coalesce(v_bal,0);
      if v_bal < v_fill * v_price then v_fill := floor(v_bal / v_price); end if;
      exit when v_fill <= 0;
      v_cash := v_fill * v_price;
      v_buyer_gems := v_fill * (1 - v_taker);
      v_seller_cash := v_cash * (1 - v_maker);
      v_tx := gen_random_uuid();
      perform public.economy_post_tx(v_tx, jsonb_build_array(
        jsonb_build_object('actor_id',p_actor,'resource_id','cash','delta',-v_cash,'kind','trade','metadata',jsonb_build_object('price',v_price)),
        jsonb_build_object('actor_id',v_sys,'resource_id','cash','delta',v_cash,'kind','trade'),
        jsonb_build_object('actor_id',v_sys,'resource_id','gems','delta',-v_buyer_gems,'kind','trade'),
        jsonb_build_object('actor_id',p_actor,'resource_id','gems','delta',v_buyer_gems,'kind','trade','metadata',jsonb_build_object('price',v_price,'fee',v_fill-v_buyer_gems)),
        jsonb_build_object('actor_id',v_sys,'resource_id','cash','delta',-v_seller_cash,'kind','trade'),
        jsonb_build_object('actor_id',v_opp.actor_id,'resource_id','cash','delta',v_seller_cash,'kind','trade','metadata',jsonb_build_object('price',v_price,'fee',v_cash-v_seller_cash))
      ));
      insert into public.economy_trades (tx_id,buy_order,sell_order,buyer_id,seller_id,gems,price,cash,fee_gems,fee_cash,venue)
        values (v_tx,null,v_opp.id,p_actor,v_opp.actor_id,v_fill,v_price,v_cash,v_fill-v_buyer_gems,v_cash-v_seller_cash,p_venue);
      v_spent := v_spent + v_cash;
    else
      select balance into v_bal from public.economy_balances where actor_id=p_actor and resource_id='gems';
      v_bal := coalesce(v_bal,0);
      if v_bal < v_fill then v_fill := floor(v_bal); end if;
      exit when v_fill <= 0;
      v_cash := v_fill * v_price;
      v_buyer_gems := v_fill * (1 - v_maker);
      v_seller_cash := v_cash * (1 - v_taker);
      v_tx := gen_random_uuid();
      perform public.economy_post_tx(v_tx, jsonb_build_array(
        jsonb_build_object('actor_id',p_actor,'resource_id','gems','delta',-v_fill,'kind','trade','metadata',jsonb_build_object('price',v_price)),
        jsonb_build_object('actor_id',v_sys,'resource_id','gems','delta',v_fill,'kind','trade'),
        jsonb_build_object('actor_id',v_sys,'resource_id','gems','delta',-v_buyer_gems,'kind','trade'),
        jsonb_build_object('actor_id',v_opp.actor_id,'resource_id','gems','delta',v_buyer_gems,'kind','trade','metadata',jsonb_build_object('price',v_price,'fee',v_fill-v_buyer_gems)),
        jsonb_build_object('actor_id',v_sys,'resource_id','cash','delta',-v_seller_cash,'kind','trade'),
        jsonb_build_object('actor_id',p_actor,'resource_id','cash','delta',v_seller_cash,'kind','trade','metadata',jsonb_build_object('price',v_price,'fee',v_cash-v_seller_cash))
      ));
      insert into public.economy_trades (tx_id,buy_order,sell_order,buyer_id,seller_id,gems,price,cash,fee_gems,fee_cash,venue)
        values (v_tx,v_opp.id,null,v_opp.actor_id,p_actor,v_fill,v_price,v_cash,v_fill-v_buyer_gems,v_cash-v_seller_cash,p_venue);
      v_recv := v_recv + v_seller_cash;
    end if;

    update public.economy_orders set gems_remaining = gems_remaining - v_fill,
      status = case when gems_remaining - v_fill <= 0 then 'filled' else 'open' end where id = v_opp.id;
    v_filled := v_filled + v_fill; v_remaining := v_remaining - v_fill;
    exit when v_remaining <= 0;
  end loop;

  if v_filled > 0 then perform public.economy_refresh_price_v(p_venue); end if;
  if v_filled <= 0 then return jsonb_build_object('success',false,'error','no liquidity'); end if;
  return jsonb_build_object('success',true,'filled',v_filled,'unfilled',v_remaining,'spent',v_spent,'received',v_recv);
end; $$;
grant execute on function public.economy_market_order_as(uuid, text, numeric, text) to authenticated;

-- 3-args = retail (rétro-compat)
create or replace function public.economy_market_order_as(p_actor uuid, p_side text, p_gems numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
begin return public.economy_market_order_as(p_actor, p_side, p_gems, 'retail'); end; $$;
grant execute on function public.economy_market_order_as(uuid, text, numeric) to authenticated;

-- 6) Poster un ordre NPC venue-aware (escrow + insert venue) ------------------
create or replace function public.economy_place_order_as(p_actor_id uuid, p_side text, p_gems numeric, p_price numeric, p_venue text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_system_id uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_cash numeric := p_gems * p_price; v_res jsonb; v_order_id uuid;
begin
  if p_side not in ('buy','sell') or p_gems <= 0 or p_price <= 0 then return null; end if;
  if p_side = 'buy' then
    v_res := public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id', p_actor_id,  'resource_id', 'cash', 'delta', -v_cash, 'kind', 'escrow'),
      jsonb_build_object('actor_id', v_system_id, 'resource_id', 'cash', 'delta',  v_cash, 'kind', 'escrow')));
  else
    v_res := public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id', p_actor_id,  'resource_id', 'gems', 'delta', -p_gems, 'kind', 'escrow'),
      jsonb_build_object('actor_id', v_system_id, 'resource_id', 'gems', 'delta',  p_gems, 'kind', 'escrow')));
  end if;
  if (v_res->>'success')::boolean is not true then return null; end if;
  insert into public.economy_orders (actor_id, side, gems, price, gems_remaining, venue)
    values (p_actor_id, p_side, p_gems, p_price, p_gems, p_venue) returning id into v_order_id;
  return v_order_id;
end; $$;

-- 4-args = retail (rétro-compat, utilisé par le tick MM retail)
create or replace function public.economy_place_order_as(p_actor_id uuid, p_side text, p_gems numeric, p_price numeric)
returns uuid language plpgsql security definer set search_path = public as $$
begin return public.economy_place_order_as(p_actor_id, p_side, p_gems, p_price, 'retail'); end; $$;

-- 7) NPC OTC : market-maker MINCE + réactif AGITÉ + garde-fou d'arbitrage -----
create or replace function public.economy_ensure_market_maker_otc()
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
begin
  select id into v_id from public.economy_actors where type='npc' and policy->>'role'='market_maker_otc' limit 1;
  if v_id is null then
    insert into public.economy_actors (type, name, policy)
      values ('npc', 'Desk OTC', jsonb_build_object(
        'role','market_maker_otc', 'spread',0.06, 'depth',8, 'anchor',100)) returning id into v_id;
    perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id',v_sys,'resource_id','gems','delta',-5e5,'kind','production'),
      jsonb_build_object('actor_id',v_id,'resource_id','gems','delta',5e5,'kind','production')));
    perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id',v_sys,'resource_id','cash','delta',-5e8,'kind','production'),
      jsonb_build_object('actor_id',v_id,'resource_id','cash','delta',5e8,'kind','production')));
  end if;
  return v_id;
end; $$;

create or replace function public.economy_ensure_reactive_npc_otc()
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
begin
  select id into v_id from public.economy_actors where type='npc' and policy->>'role'='reactive_otc' limit 1;
  if v_id is null then
    -- Plus agité que le retail : momentum fort, moins de retour moyenne, bruit ++
    insert into public.economy_actors (type, name, policy)
      values ('npc', 'Whale OTC', jsonb_build_object(
        'role','reactive_otc', 'size',25, 'w_mom',1.4, 'w_rev',0.3, 'noise',1.1,
        'anchor',100, 'last_price',0)) returning id into v_id;
    perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id',v_sys,'resource_id','gems','delta',-1e6,'kind','production'),
      jsonb_build_object('actor_id',v_id,'resource_id','gems','delta',1e6,'kind','production')));
    perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id',v_sys,'resource_id','cash','delta',-1e9,'kind','production'),
      jsonb_build_object('actor_id',v_id,'resource_id','cash','delta',1e9,'kind','production')));
  end if;
  return v_id;
end; $$;

create or replace function public.economy_ensure_arb_guard()
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
begin
  select id into v_id from public.economy_actors where type='npc' and policy->>'role'='arb_guard' limit 1;
  if v_id is null then
    insert into public.economy_actors (type, name, policy)
      values ('npc', 'Arbitragiste (garde-fou)', jsonb_build_object('role','arb_guard')) returning id into v_id;
    perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id',v_sys,'resource_id','gems','delta',-1e6,'kind','production'),
      jsonb_build_object('actor_id',v_id,'resource_id','gems','delta',1e6,'kind','production')));
    perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id',v_sys,'resource_id','cash','delta',-1e9,'kind','production'),
      jsonb_build_object('actor_id',v_id,'resource_id','cash','delta',1e9,'kind','production')));
  end if;
  return v_id;
end; $$;

-- 8) Tick OTC (appelé par economy_tick_npcs) ---------------------------------
create or replace function public.economy_tick_otc()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_mm uuid; v_react uuid; v_guard uuid; v_npc public.economy_actors;
  v_otc numeric; v_retail numeric; v_ref numeric;
  v_spread numeric; v_depth numeric; v_anchor numeric; v_buy numeric; v_sell numeric;
  v_pol jsonb; v_last numeric; v_size numeric; v_w_mom numeric; v_w_rev numeric; v_noise numeric;
  v_trend numeric; v_rev numeric; v_signal numeric; v_qty numeric; v_mres jsonb := null;
  v_gap numeric; v_thr numeric; v_asize numeric; v_ocfg jsonb; v_gres jsonb := null;
begin
  v_mm    := public.economy_ensure_market_maker_otc();
  v_react := public.economy_ensure_reactive_npc_otc();
  v_guard := public.economy_ensure_arb_guard();
  select value into v_ocfg from public.economy_config where key='otc';
  v_thr   := coalesce((v_ocfg->>'arb_threshold')::numeric, 0.05);
  v_asize := coalesce((v_ocfg->>'arb_size')::numeric, 40);

  select price into v_otc    from public.economy_price_index where id='gems_cash_otc';
  select price into v_retail from public.economy_price_index where id='gems_cash';

  -- (a) Market-maker OTC : carnet MINCE, spread LARGE
  for v_npc in select * from public.economy_actors where type='npc' and policy->>'role'='market_maker_otc' loop
    v_spread := coalesce((v_npc.policy->>'spread')::numeric,0.06);
    v_depth  := coalesce((v_npc.policy->>'depth')::numeric,8);
    v_anchor := coalesce((v_npc.policy->>'anchor')::numeric,100);
    v_ref := case when coalesce(v_otc,0)>0 then v_otc
                  when coalesce(v_retail,0)>0 then v_retail else v_anchor end;
    v_buy  := round(v_ref*(1-v_spread),4);
    v_sell := round(v_ref*(1+v_spread),4);
    perform public.economy_cancel_all_orders(v_npc.id);
    perform public.economy_place_order_as(v_npc.id,'buy', v_depth, v_buy,  'otc');
    perform public.economy_place_order_as(v_npc.id,'sell',v_depth, v_sell, 'otc');
  end loop;
  perform public.economy_match_orders_v('otc');

  -- (b) Réactif OTC : momentum sur le DERNIER cours OTC mémorisé (policy)
  select policy into v_pol from public.economy_actors where id=v_react;
  v_last  := coalesce((v_pol->>'last_price')::numeric,0);
  v_size  := coalesce((v_pol->>'size')::numeric,25);
  v_w_mom := coalesce((v_pol->>'w_mom')::numeric,1.4);
  v_w_rev := coalesce((v_pol->>'w_rev')::numeric,0.3);
  v_noise := coalesce((v_pol->>'noise')::numeric,1.1);
  v_anchor:= coalesce((v_pol->>'anchor')::numeric,100);
  select price into v_otc from public.economy_price_index where id='gems_cash_otc';

  v_trend  := case when coalesce(v_last,0)>0 then (coalesce(v_otc,0)-v_last)/v_last else 0 end;
  v_rev    := case when v_anchor>0 then (v_anchor-coalesce(v_otc,v_anchor))/v_anchor else 0 end;
  v_signal := v_w_mom*v_trend + v_w_rev*v_rev + (random()-0.5)*v_noise;
  v_qty    := greatest(1, round(v_size*(0.4+least(1.6, abs(v_signal)))));
  if v_signal >= 0 then v_mres := public.economy_market_order_as(v_react,'buy', v_qty,'otc');
  else                  v_mres := public.economy_market_order_as(v_react,'sell',v_qty,'otc'); end if;

  -- Mémoriser le cours OTC courant pour le momentum du prochain tick
  select price into v_otc from public.economy_price_index where id='gems_cash_otc';
  update public.economy_actors set policy = policy || jsonb_build_object('last_price', v_otc) where id=v_react;

  -- (c) Garde-fou d'arbitrage : n'agit QUE si |écart| > seuil (laisse la bande au joueur)
  select price into v_retail from public.economy_price_index where id='gems_cash';
  if coalesce(v_retail,0) > 0 and coalesce(v_otc,0) > 0 then
    v_gap := (v_otc - v_retail) / v_retail;
    if abs(v_gap) > v_thr then
      -- intervention proportionnelle au dépassement (douce, ne recolle pas d'un coup)
      v_qty := greatest(1, round(v_asize * least(3.0, abs(v_gap)/v_thr)));
      if v_gap > 0 then v_gres := public.economy_market_order_as(v_guard,'sell',v_qty,'otc'); -- OTC trop haut → vendre
      else              v_gres := public.economy_market_order_as(v_guard,'buy', v_qty,'otc'); -- OTC trop bas → acheter
      end if;
      select price into v_otc from public.economy_price_index where id='gems_cash_otc';
    end if;
  end if;

  return jsonb_build_object('otc_price', v_otc, 'retail_price', v_retail,
    'gap', case when coalesce(v_retail,0)>0 then round((v_otc-v_retail)/v_retail,4) else 0 end,
    'signal', round(v_signal,4), 'react', v_mres, 'guard', v_gres);
end; $$;
grant execute on function public.economy_tick_otc() to authenticated;

-- 9) Tick global = retail (corps L3b) + OTC ----------------------------------
-- ⚠️ Redéfinit economy_tick_npcs (comme l3b) : corps RETAIL identique à l3b,
--    puis « perform economy_tick_otc() ». Si l3b est re-passé, RE-PASSER ce fichier.
create or replace function public.economy_tick_npcs()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_npc public.economy_actors;
  v_ref numeric; v_spread numeric; v_depth numeric; v_anchor numeric;
  v_buy_price numeric; v_sell_price numeric; v_index_price numeric;
  v_count integer := 0; v_regime jsonb; v_otc jsonb;
  v_react uuid; v_pol jsonb; v_lookback int; v_size numeric;
  v_w_mom numeric; v_w_rev numeric; v_noise numeric; v_ranchor numeric;
  v_past numeric; v_trend numeric; v_rev numeric; v_signal numeric; v_qty numeric; v_mres jsonb;
begin
  perform public.economy_ensure_market_maker();
  v_react := public.economy_ensure_reactive_npc();
  select price into v_index_price from public.economy_price_index where id = 'gems_cash';

  -- 1) Market-makers retail
  for v_npc in select * from public.economy_actors where type='npc' and policy->>'role'='market_maker' loop
    v_spread := coalesce((v_npc.policy->>'spread')::numeric,0.04);
    v_depth  := coalesce((v_npc.policy->>'depth')::numeric,50);
    v_anchor := coalesce((v_npc.policy->>'anchor')::numeric,100);
    v_ref := case when coalesce(v_index_price,0)>0 then v_index_price else v_anchor end;
    v_buy_price  := round(v_ref*(1-v_spread),4);
    v_sell_price := round(v_ref*(1+v_spread),4);
    perform public.economy_cancel_all_orders(v_npc.id);
    perform public.economy_place_order_as(v_npc.id,'buy', v_depth, v_buy_price);
    perform public.economy_place_order_as(v_npc.id,'sell',v_depth, v_sell_price);
    v_count := v_count + 1;
  end loop;
  perform public.economy_match_orders();

  -- 2) NPC réactif retail
  select policy into v_pol from public.economy_actors where id = v_react;
  v_lookback := coalesce((v_pol->>'lookback')::int,5);
  v_size     := coalesce((v_pol->>'size')::numeric,15);
  v_w_mom    := coalesce((v_pol->>'w_mom')::numeric,1.0);
  v_w_rev    := coalesce((v_pol->>'w_rev')::numeric,0.6);
  v_noise    := coalesce((v_pol->>'noise')::numeric,0.5);
  v_ranchor  := coalesce((v_pol->>'anchor')::numeric,100);
  select price into v_index_price from public.economy_price_index where id='gems_cash';
  select price into v_past from (
    select price, captured_at from public.economy_price_history order by captured_at desc limit v_lookback
  ) s order by captured_at asc limit 1;
  v_trend  := case when coalesce(v_past,0)>0 then (coalesce(v_index_price,0) - v_past)/v_past else 0 end;
  v_rev    := case when v_ranchor>0 then (v_ranchor - coalesce(v_index_price,v_ranchor))/v_ranchor else 0 end;
  v_signal := v_w_mom*v_trend + v_w_rev*v_rev + (random()-0.5)*v_noise;
  v_qty    := greatest(1, round(v_size * (0.4 + least(1.6, abs(v_signal)))));
  if v_signal >= 0 then v_mres := public.economy_market_order_as(v_react, 'buy',  v_qty);
  else                  v_mres := public.economy_market_order_as(v_react, 'sell', v_qty); end if;

  -- 3) Historique + régime (retail = référence du régime global)
  select price into v_index_price from public.economy_price_index where id='gems_cash';
  insert into public.economy_price_history (price, volume)
    select v_index_price, volume_recent from public.economy_price_index where id='gems_cash';
  v_regime := public.economy_update_regime();

  -- 4) Venue OTC (book séparé)
  v_otc := public.economy_tick_otc();

  return jsonb_build_object(
    'npcs_ticked', v_count + 1, 'ref_price', v_ref,
    'signal', round(v_signal,4), 'react', v_mres, 'regime', v_regime, 'otc', v_otc);
end; $$;
grant execute on function public.economy_tick_npcs() to authenticated;

-- 10) API UI OTC (book, ticker, ordres joueur) -------------------------------
-- Ticker OTC : cours OTC + cours retail + écart (pour le widget d'arbitrage)
create or replace function public.economy_ticker_otc()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_o public.economy_price_index; v_r numeric;
begin
  select * into v_o from public.economy_price_index where id='gems_cash_otc';
  select price into v_r from public.economy_price_index where id='gems_cash';
  return jsonb_build_object(
    'otc_price', coalesce(v_o.price,0), 'retail_price', coalesce(v_r,0),
    'spread', case when coalesce(v_r,0)>0 then round((coalesce(v_o.price,0)-v_r)/v_r,4) else 0 end,
    'volume_recent', coalesce(v_o.volume_recent,0), 'trades_count', coalesce(v_o.trades_count,0),
    'updated_at', v_o.updated_at);
end; $$;
grant execute on function public.economy_ticker_otc() to authenticated, anon;

-- Carnet OTC agrégé
create or replace function public.economy_orderbook_otc()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_bids jsonb; v_asks jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) into v_bids from (
    select price, sum(gems_remaining) as gems from public.economy_orders
    where side='buy' and status='open' and venue='otc' group by price order by price desc limit 10) r;
  select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) into v_asks from (
    select price, sum(gems_remaining) as gems from public.economy_orders
    where side='sell' and status='open' and venue='otc' group by price order by price asc limit 10) r;
  return jsonb_build_object('bids', v_bids, 'asks', v_asks);
end; $$;
grant execute on function public.economy_orderbook_otc() to authenticated, anon;

-- Ordre Limite OTC (joueur) : taille MINIMALE imposée (gros ordres)
create or replace function public.economy_place_order_otc(p_side text, p_gems numeric, p_price numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid; v_min numeric; v_oid uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if p_side not in ('buy','sell') then raise exception 'invalid side'; end if;
  if p_gems <= 0 or p_price <= 0 then raise exception 'invalid amounts'; end if;
  select coalesce((value->>'min_gems_per_order')::numeric,200) into v_min from public.economy_config where key='otc';
  if p_gems < v_min then return jsonb_build_object('success',false,'error','min '||v_min||' gems sur l''OTC'); end if;

  v_actor := public.economy_ensure_player();
  v_oid := public.economy_place_order_as(v_actor, p_side, p_gems, p_price, 'otc');
  if v_oid is null then return jsonb_build_object('success',false,'error','escrow refusé (solde insuffisant)'); end if;
  perform public.economy_match_orders_v('otc');
  return jsonb_build_object('success',true,'order_id',v_oid);
end; $$;
grant execute on function public.economy_place_order_otc(text, numeric, numeric) to authenticated;

-- Ordre Market OTC (joueur) : taille MINIMALE imposée
create or replace function public.economy_market_order_otc(p_side text, p_gems numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid; v_min numeric;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select coalesce((value->>'min_gems_per_order')::numeric,200) into v_min from public.economy_config where key='otc';
  if coalesce(p_gems,0) < v_min then return jsonb_build_object('success',false,'error','min '||v_min||' gems sur l''OTC'); end if;
  v_actor := public.economy_ensure_player();
  return public.economy_market_order_as(v_actor, p_side, p_gems, 'otc');
end; $$;
grant execute on function public.economy_market_order_otc(text, numeric) to authenticated;
