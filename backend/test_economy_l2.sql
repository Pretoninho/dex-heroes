-- ============================================================================
-- Dex Heroes — Tests L2 (Marché sur ledger + index de prix)
-- À coller dans Supabase APRÈS economy.sql + economy_l2.sql
-- ============================================================================
-- Ré-exécutable : crée des acteurs neufs à chaque passe et asserte sur leurs
-- IDs (pas par nom). Les tables ledger/trades étant immuables, on n'efface rien.
-- ============================================================================

do $$
declare
  v_a uuid; v_b uuid;
  v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_matches integer;
  v_seller_gems numeric; v_seller_cash numeric;
  v_buyer_gems numeric;  v_buyer_cash numeric;
  v_price numeric;
begin
  -- 1) Deux acteurs neufs
  insert into public.economy_actors (type, name) values ('player', 'mkt_seller_' || gen_random_uuid()::text) returning id into v_a;
  insert into public.economy_actors (type, name) values ('player', 'mkt_buyer_'  || gen_random_uuid()::text) returning id into v_b;

  -- 2) Dotation (faucet via SYSTÈME) : seller 100 gems, buyer 10000 cash
  perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id', v_sys, 'resource_id', 'gems', 'delta', -100, 'kind', 'production'),
    jsonb_build_object('actor_id', v_a,   'resource_id', 'gems', 'delta',  100, 'kind', 'production')
  ));
  perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id', v_sys, 'resource_id', 'cash', 'delta', -10000, 'kind', 'production'),
    jsonb_build_object('actor_id', v_b,   'resource_id', 'cash', 'delta',  10000, 'kind', 'production')
  ));
  raise notice '--- Dotation : seller=100 gems, buyer=10000 cash ---';

  -- 3) SELLER : vendre 50 gems @ 100 (escrow gems -> SYSTÈME)
  perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id', v_a,   'resource_id', 'gems', 'delta', -50, 'kind', 'escrow'),
    jsonb_build_object('actor_id', v_sys, 'resource_id', 'gems', 'delta',  50, 'kind', 'escrow')
  ));
  insert into public.economy_orders (actor_id, side, gems, price, gems_remaining) values (v_a, 'sell', 50, 100, 50);
  raise notice 'SELL posté : 50 gems @ 100';

  -- 4) BUYER : acheter 30 gems @ 120 (escrow cash -> SYSTÈME)
  perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id', v_b,   'resource_id', 'cash', 'delta', -(30*120), 'kind', 'escrow'),
    jsonb_build_object('actor_id', v_sys, 'resource_id', 'cash', 'delta',  (30*120), 'kind', 'escrow')
  ));
  insert into public.economy_orders (actor_id, side, gems, price, gems_remaining) values (v_b, 'buy', 30, 120, 30);
  raise notice 'BUY posté : 30 gems @ 120 (croise le sell @ 100)';

  -- 5) Matcher
  v_matches := public.economy_match_orders();
  raise notice 'Matches exécutés : %', v_matches;

  -- 6) Lire les soldes finaux
  select balance into v_seller_gems from public.economy_balances where actor_id = v_a and resource_id = 'gems';
  select balance into v_seller_cash from public.economy_balances where actor_id = v_a and resource_id = 'cash';
  select balance into v_buyer_gems  from public.economy_balances where actor_id = v_b and resource_id = 'gems';
  select balance into v_buyer_cash  from public.economy_balances where actor_id = v_b and resource_id = 'cash';
  select price into v_price from public.economy_price_index where id = 'gems_cash';

  raise notice 'SELLER : % gems, % cash (attendu 50 / 3000)', v_seller_gems, v_seller_cash;
  raise notice 'BUYER  : % gems, % cash (attendu 30 / 7000)', v_buyer_gems, v_buyer_cash;
  raise notice 'COURS  : % (attendu 100)', v_price;

  -- 7) ASSERTIONS : lèvent une exception si un solde est faux
  if v_seller_gems != 50   then raise exception 'FAIL seller gems: % (attendu 50)', v_seller_gems; end if;
  if v_seller_cash != 3000 then raise exception 'FAIL seller cash: % (attendu 3000)', v_seller_cash; end if;
  if v_buyer_gems != 30    then raise exception 'FAIL buyer gems: % (attendu 30)', v_buyer_gems; end if;
  if v_buyer_cash != 7000  then raise exception 'FAIL buyer cash: % (attendu 7000)', v_buyer_cash; end if;
  if v_price != 100        then raise exception 'FAIL price: % (attendu 100)', v_price; end if;

  raise notice '✓ ASSERTIONS L2 OK : soldes + cours corrects, conservation respectée';
end; $$;

-- 8) Affichage du dernier fait de trade + cours
select 'DERNIER TRADE' as info, gems, price, cash from public.economy_trades order by executed_at desc limit 1;
select 'COURS' as info, price, volume_recent, trades_count from public.economy_price_index where id = 'gems_cash';

select 'Tests L2 finished ✓ (assertions passées)' as result;
