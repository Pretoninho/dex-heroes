-- ============================================================================
-- Dex Heroes — Tests L2 (Marché sur ledger + index de prix)
-- À coller dans Supabase APRÈS economy.sql + economy_l2.sql
-- ============================================================================
-- Note : ces tests appellent post_tx directement (pas via auth) pour simuler
-- deux joueurs. On crée 2 acteurs, on les dote, on poste des ordres
-- manuellement (sans economy_place_order qui exige auth.uid()), puis on matche.

do $$
declare
  v_a uuid; v_b uuid;
  v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_tx uuid;
  v_matches integer;
  v_price jsonb;
begin
  -- 1) Créer 2 acteurs de test marché
  insert into public.economy_actors (type, name) values ('player', 'mkt_seller') returning id into v_a;
  insert into public.economy_actors (type, name) values ('player', 'mkt_buyer') returning id into v_b;

  -- 2) Doter : le vendeur a 100 gems, l'acheteur a 10000 cash (production = SYSTEM)
  perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id', v_a, 'resource_id', 'gems', 'delta', 100, 'kind', 'production')
  ));
  perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id', v_b, 'resource_id', 'cash', 'delta', 10000, 'kind', 'production')
  ));
  raise notice '--- Dotation faite : seller=100 gems, buyer=10000 cash ---';

  -- 3) SELLER poste un ordre de vente : 50 gems @ 100 cash/gemme (escrow gems -> SYSTEM)
  v_tx := gen_random_uuid();
  perform public.economy_post_tx(v_tx, jsonb_build_array(
    jsonb_build_object('actor_id', v_a,   'resource_id', 'gems', 'delta', -50, 'kind', 'escrow'),
    jsonb_build_object('actor_id', v_sys, 'resource_id', 'gems', 'delta',  50, 'kind', 'escrow')
  ));
  insert into public.economy_orders (actor_id, side, gems, price, gems_remaining)
    values (v_a, 'sell', 50, 100, 50);
  raise notice 'SELL posté : 50 gems @ 100';

  -- 4) BUYER poste un ordre d'achat : 30 gems @ 120 cash/gemme (escrow cash -> SYSTEM)
  v_tx := gen_random_uuid();
  perform public.economy_post_tx(v_tx, jsonb_build_array(
    jsonb_build_object('actor_id', v_b,   'resource_id', 'cash', 'delta', -30*120, 'kind', 'escrow'),
    jsonb_build_object('actor_id', v_sys, 'resource_id', 'cash', 'delta',  30*120, 'kind', 'escrow')
  ));
  insert into public.economy_orders (actor_id, side, gems, price, gems_remaining)
    values (v_b, 'buy', 30, 120, 30);
  raise notice 'BUY posté : 30 gems @ 120 (croise le sell @ 100)';

  -- 5) Matcher
  v_matches := public.economy_match_orders();
  raise notice 'Matches exécutés : %', v_matches;

  -- 6) Vérifier le cours
  v_price := public.economy_get_price();
  raise notice 'Cours après trade : %', v_price;
end; $$;

-- 7) Résultats : soldes finaux
select 'SOLDES FINAUX (attendu : seller -30gems +3000cash ; buyer +30gems ; cash escrow rendu)' as test;
select ea.name, eb.resource_id, eb.balance
  from public.economy_balances eb
  join public.economy_actors ea on ea.id = eb.actor_id
  where ea.name in ('mkt_seller', 'mkt_buyer')
  order by ea.name, eb.resource_id;
-- Attendu :
--   mkt_seller : gems = 50 (100 - 50 escrow), cash = 3000 (30 * 100)
--   mkt_buyer  : gems = 30, cash = 10000 - 3600 (escrow) + 600 (refund 30*(120-100)) = 7000

-- 8) Le fait de trade
select 'FAIT DE TRADE' as test;
select gems, price, cash, executed_at from public.economy_trades order by executed_at desc limit 5;
-- Attendu : 30 gems @ 100 = 3000 cash

-- 9) Le cours
select 'COURS (index de prix)' as test;
select * from public.economy_price_index;
-- Attendu : price = 100 (le seul trade), volume_recent = 30, trades_count = 1

-- 10) Vérifier conservation globale : la somme de TOUS les soldes par ressource
--     doit égaler ce que SYSTEM a injecté (100 gems + 10000 cash), SYSTEM inclus = 0 net
select 'CONSERVATION GLOBALE (somme tous soldes hors injections SYSTEM)' as test;
select eb.resource_id, sum(eb.balance) as total
  from public.economy_balances eb
  join public.economy_actors ea on ea.id = eb.actor_id
  where ea.name in ('mkt_seller', 'mkt_buyer')
  group by eb.resource_id;
-- Attendu : gems = 80 (50 seller + 30 buyer ; 20 gems restent en escrow chez SYSTEM)
--           cash = 10000 (3000 seller + 7000 buyer ; 0 en escrow car tout rendu/réglé)

select 'Tests L2 finished ✓' as result;
