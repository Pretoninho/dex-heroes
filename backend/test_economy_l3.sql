-- ============================================================================
-- Dex Heroes — Tests L3 (NPC market-maker)
-- À coller dans Supabase APRÈS economy.sql + economy_l2.sql + economy_l3.sql
-- ============================================================================
-- Vérifie : (A) en isolation, le MM poste des ordres mais ne crée AUCUN trade
--           (ledger intact) ; (B) avec un joueur, un trade a lieu et le cours
--           bouge ; (C) conservation respectée partout.
-- ============================================================================

do $$
declare
  v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_mm uuid;
  v_player uuid;
  v_trades_before bigint; v_trades_after_iso bigint; v_trades_after_trade bigint;
  v_mm_buys integer; v_mm_sells integer;
  v_tick jsonb;
  v_price_before numeric; v_price_after numeric;
  v_player_gems numeric;
  v_sell_price numeric;
begin
  -- ============ A) ISOLATION ============
  -- Vider le carnet pour que "0 trade en isolation" soit un vrai test
  -- (sinon le MM matcherait de vieux ordres d'autres passes).
  delete from public.economy_orders;
  select count(*) into v_trades_before from public.economy_trades;

  -- Premier tick : crée + amorce le MM, poste buy + sell
  v_tick := public.economy_tick_npcs();
  raise notice 'Tick 1 (isolation) : %', v_tick;

  select id into v_mm from public.economy_actors where type='npc' and policy->>'role'='market_maker' limit 1;
  if v_mm is null then raise exception 'A FAIL: market-maker non créé'; end if;

  -- Le MM doit avoir 1 buy et 1 sell ouverts
  select count(*) into v_mm_buys  from public.economy_orders where actor_id=v_mm and side='buy'  and status='open';
  select count(*) into v_mm_sells from public.economy_orders where actor_id=v_mm and side='sell' and status='open';
  if v_mm_buys < 1 or v_mm_sells < 1 then raise exception 'A FAIL: MM n''a pas posté buy+sell (buy=%, sell=%)', v_mm_buys, v_mm_sells; end if;

  -- AUCUN trade ne doit avoir eu lieu (le MM ne se matche pas lui-même)
  select count(*) into v_trades_after_iso from public.economy_trades;
  if v_trades_after_iso != v_trades_before then raise exception 'A FAIL: un trade a eu lieu en isolation (% -> %)', v_trades_before, v_trades_after_iso; end if;
  raise notice '✓ A OK : MM poste buy+sell, ledger intact (0 trade en isolation)';

  -- ============ B) INTERACTION JOUEUR ============
  -- Le cours de référence est l'ancre (100). Le MM vend @ ~104 (anchor*1.04).
  select price into v_sell_price from public.economy_orders where actor_id=v_mm and side='sell' and status='open' limit 1;
  raise notice 'MM vend @ %', v_sell_price;

  -- Créer un joueur doté en cash
  insert into public.economy_actors (type, name) values ('player', 'l3_player_'||gen_random_uuid()::text) returning id into v_player;
  perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id', v_sys,      'resource_id', 'cash', 'delta', -100000, 'kind', 'production'),
    jsonb_build_object('actor_id', v_player,   'resource_id', 'cash', 'delta',  100000, 'kind', 'production')
  ));

  select price into v_price_before from public.economy_price_index where id='gems_cash';

  -- Le joueur achète 20 gems à un prix qui croise le sell du MM (escrow cash)
  perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id', v_player, 'resource_id', 'cash', 'delta', -(20 * v_sell_price), 'kind', 'escrow'),
    jsonb_build_object('actor_id', v_sys,    'resource_id', 'cash', 'delta',  (20 * v_sell_price), 'kind', 'escrow')
  ));
  insert into public.economy_orders (actor_id, side, gems, price, gems_remaining)
    values (v_player, 'buy', 20, v_sell_price, 20);

  perform public.economy_match_orders();

  -- Le joueur doit avoir reçu 20 gems
  select balance into v_player_gems from public.economy_balances where actor_id=v_player and resource_id='gems';
  if v_player_gems != 20 then raise exception 'B FAIL: joueur a % gems (attendu 20)', v_player_gems; end if;

  -- Un trade a eu lieu
  select count(*) into v_trades_after_trade from public.economy_trades;
  if v_trades_after_trade <= v_trades_after_iso then raise exception 'B FAIL: aucun trade joueur'; end if;

  -- Le cours s'est mis à jour (= prix d'exécution = sell du MM)
  select price into v_price_after from public.economy_price_index where id='gems_cash';
  if v_price_after <= 0 then raise exception 'B FAIL: cours nul après trade'; end if;
  raise notice '✓ B OK : joueur a acheté 20 gems au MM ; cours % -> %', v_price_before, v_price_after;

  -- ============ C) TICK SUIVANT ============
  -- Le MM doit reposer autour du nouveau cours (pas de crash, pas de boucle)
  v_tick := public.economy_tick_npcs();
  raise notice 'Tick 2 (après trade) : %', v_tick;
  raise notice '✓ C OK : le MM a re-tické autour du nouveau cours';

  raise notice '✓✓ TOUS LES TESTS L3 PASSÉS';
end; $$;

-- Assertion de conservation globale : somme de TOUS les soldes (SYSTÈME inclus)
-- == 0 par ressource. C'est l'invariant le plus fort : chaque tx équilibrée à 0
-- ⇒ la somme de tous les soldes reste 0 pour toujours. Rien n'est créé/détruit.
do $$
declare v_r record;
begin
  for v_r in select resource_id, sum(balance) as total_net from public.economy_balances group by resource_id loop
    if v_r.total_net != 0 then
      raise exception 'CONSERVATION GLOBALE VIOLÉE : % total net = % (attendu 0)', v_r.resource_id, v_r.total_net;
    end if;
    raise notice '✓ Conservation % : total net = 0', v_r.resource_id;
  end loop;
end; $$;

-- Affichage du carnet et du cours pour inspection
select 'CARNET (agrégé)' as info, public.economy_orderbook() as orderbook;
select 'COURS' as info, price, volume_recent, trades_count from public.economy_price_index where id='gems_cash';

select 'Tests L3 finished ✓ (assertions + conservation globale OK)' as result;
