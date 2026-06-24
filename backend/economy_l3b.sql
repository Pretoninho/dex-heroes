-- ============================================================================
-- Dex Heroes — L3b : NPC réactif (fait vivre le cours)
-- À coller APRÈS economy.sql + l2 + l3 + l4 + market_api + fees + market_order
-- ============================================================================
-- Le market-maker (L3) STABILISE (carnet permanent). Le réactif (L3b) MET DU
-- MOUVEMENT : chaque tick il lit la tendance et PREND de la liquidité au MM
-- dans le sens du signal → des trades s'exécutent → le cours bouge tout seul,
-- même sans joueurs. Signal = momentum + retour à la moyenne + bruit.
-- Conservation préservée (tout passe par economy_post_tx).
-- ============================================================================

-- 1) Ordre Market INTERNE (pour un acteur donné, sans auth) ------------------
-- Même logique que economy_market_order, mais l'acteur est passé en paramètre.
create or replace function public.economy_market_order_as(p_actor uuid, p_side text, p_gems numeric)
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

  select value into v_cfg from public.economy_config where key='fees';
  v_maker := coalesce((v_cfg->>'maker')::numeric,0.001);
  v_taker := coalesce((v_cfg->>'taker')::numeric,0.002);
  v_remaining := p_gems;

  loop
    v_guard := v_guard + 1; exit when v_guard > 500;
    if p_side = 'buy' then
      select * into v_opp from public.economy_orders
        where side='sell' and status='open' and gems_remaining>0 and actor_id<>p_actor
        order by price asc, created_at asc limit 1;
    else
      select * into v_opp from public.economy_orders
        where side='buy' and status='open' and gems_remaining>0 and actor_id<>p_actor
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
      insert into public.economy_trades (tx_id,buy_order,sell_order,buyer_id,seller_id,gems,price,cash,fee_gems,fee_cash)
        values (v_tx,null,v_opp.id,p_actor,v_opp.actor_id,v_fill,v_price,v_cash,v_fill-v_buyer_gems,v_cash-v_seller_cash);
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
      insert into public.economy_trades (tx_id,buy_order,sell_order,buyer_id,seller_id,gems,price,cash,fee_gems,fee_cash)
        values (v_tx,v_opp.id,null,v_opp.actor_id,p_actor,v_fill,v_price,v_cash,v_fill-v_buyer_gems,v_cash-v_seller_cash);
      v_recv := v_recv + v_seller_cash;
    end if;

    update public.economy_orders set gems_remaining = gems_remaining - v_fill,
      status = case when gems_remaining - v_fill <= 0 then 'filled' else 'open' end where id = v_opp.id;
    v_filled := v_filled + v_fill; v_remaining := v_remaining - v_fill;
    exit when v_remaining <= 0;
  end loop;

  if v_filled > 0 then perform public.economy_refresh_price(); end if;
  if v_filled <= 0 then return jsonb_build_object('success',false,'error','no liquidity'); end if;
  return jsonb_build_object('success',true,'filled',v_filled,'unfilled',v_remaining,'spent',v_spent,'received',v_recv);
end; $$;

-- economy_market_order (joueur) délègue au coeur interne
create or replace function public.economy_market_order(p_side text, p_gems numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  v_actor := public.economy_ensure_player();
  return public.economy_market_order_as(v_actor, p_side, p_gems);
end; $$;
grant execute on function public.economy_market_order(text, numeric) to authenticated;

-- 2) NPC réactif : création + amorçage --------------------------------------
create or replace function public.economy_ensure_reactive_npc()
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid; v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_seed_gems numeric := 1e6; v_seed_cash numeric := 1e9;
begin
  select id into v_id from public.economy_actors where type='npc' and policy->>'role'='reactive' limit 1;
  if v_id is null then
    insert into public.economy_actors (type, name, policy)
      values ('npc', 'Trader algo', jsonb_build_object(
        'role','reactive', 'lookback',5, 'size',15,
        'w_mom',1.0, 'w_rev',0.6, 'noise',0.5, 'anchor',100
      )) returning id into v_id;
    perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id',v_sys,'resource_id','gems','delta',-v_seed_gems,'kind','production'),
      jsonb_build_object('actor_id',v_id,'resource_id','gems','delta',v_seed_gems,'kind','production')
    ));
    perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id',v_sys,'resource_id','cash','delta',-v_seed_cash,'kind','production'),
      jsonb_build_object('actor_id',v_id,'resource_id','cash','delta',v_seed_cash,'kind','production')
    ));
  end if;
  return v_id;
end; $$;

-- 3) Tick complet : market-maker + réactif + historique + régime -------------
create or replace function public.economy_tick_npcs()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_npc public.economy_actors;
  v_ref numeric; v_spread numeric; v_depth numeric; v_anchor numeric;
  v_buy_price numeric; v_sell_price numeric; v_index_price numeric;
  v_count integer := 0; v_regime jsonb;
  v_react uuid; v_pol jsonb; v_lookback int; v_size numeric;
  v_w_mom numeric; v_w_rev numeric; v_noise numeric; v_ranchor numeric;
  v_past numeric; v_trend numeric; v_rev numeric; v_signal numeric; v_qty numeric; v_mres jsonb;
begin
  perform public.economy_ensure_market_maker();
  v_react := public.economy_ensure_reactive_npc();
  select price into v_index_price from public.economy_price_index where id = 'gems_cash';

  -- 1) Market-makers : reposent leur carnet autour du cours
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

  -- Match (ordres de joueurs éventuels vs MM)
  perform public.economy_match_orders();

  -- 2) NPC réactif : signal → prend de la liquidité → fait bouger le cours
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

  if v_signal >= 0 then
    v_mres := public.economy_market_order_as(v_react, 'buy',  v_qty);
  else
    v_mres := public.economy_market_order_as(v_react, 'sell', v_qty);
  end if;

  -- 3) Snapshot de l'historique + réévaluation du régime
  select price into v_index_price from public.economy_price_index where id='gems_cash';
  insert into public.economy_price_history (price, volume)
    select v_index_price, volume_recent from public.economy_price_index where id='gems_cash';
  v_regime := public.economy_update_regime();

  return jsonb_build_object(
    'npcs_ticked', v_count + 1, 'ref_price', v_ref,
    'signal', round(v_signal,4), 'react', v_mres, 'regime', v_regime
  );
end; $$;
grant execute on function public.economy_tick_npcs() to authenticated;
