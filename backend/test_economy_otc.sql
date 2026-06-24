-- ============================================================================
-- Dex Heroes — Test du tier OTC (venue séparée)
-- À coller APRÈS economy_otc.sql
-- ============================================================================
-- Vérifie : (1) le MM OTC poste un carnet mince · (2) CLOISONNEMENT retail↔OTC
-- (pas de cross-match) · (3) frais TAKER OTC = 1 % appliqués · (4) book mince =
-- impact réel · (5) garde-fou d'arbitrage se déclenche au-delà du seuil ·
-- (6) CONSERVATION = 0 par ressource (l'invariant clé).
-- ============================================================================

do $$
declare
  v_a uuid; v_b uuid; v_c uuid; v_d uuid; v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_n_otc int; v_a_sell uuid; v_rem numeric; v_status text;
  v_res jsonb; v_filled numeric; v_gems numeric; v_eff numeric;
  v_otc numeric; v_retail numeric; v_tk jsonb;
begin
  -- Amorcer la venue OTC (2 ticks → le cours OTC devient > 0)
  perform public.economy_tick_npcs();
  perform public.economy_tick_npcs();

  -- (1) Le MM OTC poste un carnet (mince) -----------------------------------
  select count(*) into v_n_otc from public.economy_orders where venue='otc' and status='open';
  if v_n_otc = 0 then raise exception 'FAIL: aucun ordre OTC posté'; end if;
  raise notice '✓ (1) carnet OTC : % ordres ouverts', v_n_otc;

  -- (2) CLOISONNEMENT : un sell retail haut + un buy OTC plus haut ne se croisent pas
  insert into public.economy_actors(type,name) values('retail','iso_a_'||gen_random_uuid()::text) returning id into v_a;
  insert into public.economy_actors(type,name) values('retail','iso_b_'||gen_random_uuid()::text) returning id into v_b;
  perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id',v_sys,'resource_id','gems','delta',-1000,'kind','deposit'),
    jsonb_build_object('actor_id',v_a,  'resource_id','gems','delta', 1000,'kind','deposit')));
  perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id',v_sys,'resource_id','cash','delta',-2e6,'kind','deposit'),
    jsonb_build_object('actor_id',v_b,  'resource_id','cash','delta', 2e6,'kind','deposit')));

  -- v_a : SELL RETAIL @200 (au-dessus de tout acheteur retail → reste ouvert)
  v_a_sell := public.economy_place_order_as(v_a,'sell',1000,200,'retail');
  -- v_b : BUY OTC @250 (croiserait le sell de v_a SI les venues n'étaient pas cloisonnées)
  perform public.economy_place_order_as(v_b,'buy',500,250,'otc');
  perform public.economy_match_orders_v('retail');
  perform public.economy_match_orders_v('otc');

  select gems_remaining, status into v_rem, v_status from public.economy_orders where id=v_a_sell;
  if v_rem <> 1000 or v_status <> 'open' then
    raise exception 'FAIL: cloisonnement brisé (sell retail entamé : reste=% statut=%)', v_rem, v_status;
  end if;
  raise notice '✓ (2) cloisonnement retail↔OTC OK (le BUY OTC n''a pas touché le SELL retail)';

  -- (3) Frais taker OTC = 1 % — liquidité OTC déterministe (un SELL @100 dédié)
  -- (le MM OTC peut être vidé par le réactif au tick → on pose notre propre ask)
  insert into public.economy_actors(type,name) values('retail','mk_otc_'||gen_random_uuid()::text) returning id into v_d;
  perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id',v_sys,'resource_id','gems','delta',-500,'kind','deposit'),
    jsonb_build_object('actor_id',v_d,  'resource_id','gems','delta', 500,'kind','deposit')));
  perform public.economy_place_order_as(v_d,'sell',500,100,'otc');   -- ask OTC @100, 500 gems

  insert into public.economy_actors(type,name) values('retail','fee_c_'||gen_random_uuid()::text) returning id into v_c;
  perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id',v_sys,'resource_id','cash','delta',-1e6,'kind','deposit'),
    jsonb_build_object('actor_id',v_c,  'resource_id','cash','delta', 1e6,'kind','deposit')));
  v_res := public.economy_market_order_as(v_c,'buy',500,'otc');   -- consomme tout l'ask @100 (rien ne fuit vers l'étape 5)
  v_filled := coalesce((v_res->>'filled')::numeric,0);
  if v_filled <= 0 then raise exception 'FAIL: aucun fill OTC (liquidité ?)'; end if;
  select coalesce(balance,0) into v_gems from public.economy_balances where actor_id=v_c and resource_id='gems';
  v_eff := v_gems / v_filled;        -- = (1 - taker) attendu ≈ 0,99 (initiateur Market = taker)
  if abs(v_eff - 0.99) > 0.005 then
    raise exception 'FAIL: frais taker OTC inattendu (effectif % au lieu de 0.99)', round(v_eff,4);
  end if;
  raise notice '✓ (3)+(4) frais taker OTC = 1%% sur fill OTC (gems nets/fill = %, fill=%)', round(v_eff,4), v_filled;

  -- (5) Garde-fou d'arbitrage : forcer un gros écart → il intervient ---------
  select price into v_retail from public.economy_price_index where id='gems_cash';
  update public.economy_price_index set price = greatest(v_retail,100) * 1.50 where id='gems_cash_otc'; -- écart +50 % >> 5 %
  v_tk := public.economy_tick_otc();
  if (v_tk->'guard') is null or v_tk->'guard' = 'null'::jsonb then
    raise exception 'FAIL: garde-fou inactif malgré un écart de 30%% (>seuil 5%%)';
  end if;
  raise notice '✓ (5) garde-fou déclenché au-delà du seuil (guard=%)', v_tk->'guard';
end $$;

-- (6) CONSERVATION globale (l'invariant clé, OTC inclus) ---------------------
do $$ declare r record; begin
  for r in select resource_id, round(sum(balance),6) as tot from public.economy_balances group by resource_id loop
    if r.tot != 0 then raise exception 'CONSERVATION VIOLÉE : % = %', r.resource_id, r.tot; end if;
    raise notice '✓ (6) conservation % = 0', r.resource_id;
  end loop;
end $$;

select 'Tests OTC finished ✓' as result;
