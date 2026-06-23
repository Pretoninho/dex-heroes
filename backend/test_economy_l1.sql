-- ============================================================================
-- Dex Heroes — Tests L1 (Ledger + Acteurs)
-- À coller dans Supabase après avoir exécuté economy.sql
-- ============================================================================

-- Nettoyer les données de test (optionnel)
-- delete from public.economy_ledger where tx_id in (...);
-- delete from public.economy_balances where actor_id in (...);

-- 0) État initial
select 'État initial' as test;
select * from public.economy_resources;
select * from public.economy_actors;

-- 1) Créer 2 acteurs de test
select 'Créer 2 acteurs test' as test;
do $$
declare
  v_actor_a uuid;
  v_actor_b uuid;
begin
  insert into public.economy_actors (type, name) values ('player', 'test_actor_a')
    returning id into v_actor_a;
  insert into public.economy_actors (type, name) values ('player', 'test_actor_b')
    returning id into v_actor_b;
  raise notice 'Created actors: A=%, B=%', v_actor_a, v_actor_b;
end; $$;

-- Récupérer les IDs (pour référence)
select id, type, name from public.economy_actors where type = 'player' order by created_at desc limit 2;

-- 2) Initialiser balances des deux acteurs
select 'Initialiser balances' as test;
insert into public.economy_balances (actor_id, resource_id, balance)
  select ea.id, 'cash', 0 from public.economy_actors ea where ea.type = 'player' and ea.name in ('test_actor_a', 'test_actor_b')
  on conflict (actor_id, resource_id) do nothing;
insert into public.economy_balances (actor_id, resource_id, balance)
  select ea.id, 'gems', 0 from public.economy_actors ea where ea.type = 'player' and ea.name in ('test_actor_a', 'test_actor_b')
  on conflict (actor_id, resource_id) do nothing;

select ea.name, eb.resource_id, eb.balance
  from public.economy_balances eb
  join public.economy_actors ea on ea.id = eb.actor_id
  where ea.type = 'player' and ea.name in ('test_actor_a', 'test_actor_b')
  order by ea.name, eb.resource_id;

-- 3) TEST 1 : TX équilibrée (A +10 gems, B -10 gems)
select 'TEST 1 : TX équilibrée (transfer gems: A+10, B-10)' as test;
do $$
declare
  v_actor_a uuid;
  v_actor_b uuid;
  v_tx_id uuid;
  v_result jsonb;
  v_entries jsonb;
begin
  select id into v_actor_a from public.economy_actors where type = 'player' and name = 'test_actor_a';
  select id into v_actor_b from public.economy_actors where type = 'player' and name = 'test_actor_b';
  v_tx_id := gen_random_uuid();

  -- Initialiser A avec 50 gems
  v_entries := jsonb_build_array(
    jsonb_build_object(
      'actor_id', v_actor_a,
      'resource_id', 'gems',
      'delta', 50,
      'kind', 'production'
    )
  );
  v_result := public.economy_post_tx(v_tx_id, v_entries);
  raise notice 'Init A: %', v_result;

  -- Transfer équilibré : A -10 gems, B +10 gems
  v_tx_id := gen_random_uuid();
  v_entries := jsonb_build_array(
    jsonb_build_object(
      'actor_id', v_actor_a,
      'resource_id', 'gems',
      'delta', -10,
      'kind', 'transfer'
    ),
    jsonb_build_object(
      'actor_id', v_actor_b,
      'resource_id', 'gems',
      'delta', 10,
      'kind', 'transfer'
    )
  );
  v_result := public.economy_post_tx(v_tx_id, v_entries);
  raise notice 'Transfer result: %', v_result;
end; $$;

-- Vérifier les balances après TX1
select ea.name, eb.resource_id, eb.balance
  from public.economy_balances eb
  join public.economy_actors ea on ea.id = eb.actor_id
  where ea.type = 'player' and ea.name in ('test_actor_a', 'test_actor_b')
  order by ea.name, eb.resource_id;

-- Vérifier le ledger
select el.actor_id, ea.name, el.resource_id, el.delta, el.kind
  from public.economy_ledger el
  join public.economy_actors ea on ea.id = el.actor_id
  where ea.type = 'player' and ea.name in ('test_actor_a', 'test_actor_b')
  order by el.created_at;

-- 4) TEST 2 : TX déséquilibrée (doit REFUSER)
select 'TEST 2 : TX déséquilibrée (A+10, B+5, C-20) → DOIT REFUSER' as test;
do $$
declare
  v_actor_a uuid;
  v_actor_b uuid;
  v_actor_c uuid;
  v_tx_id uuid;
  v_result jsonb;
  v_entries jsonb;
begin
  select id into v_actor_a from public.economy_actors where type = 'player' and name = 'test_actor_a';
  select id into v_actor_b from public.economy_actors where type = 'player' and name = 'test_actor_b';

  -- Créer un 3e acteur
  insert into public.economy_actors (type, name) values ('player', 'test_actor_c')
    returning id into v_actor_c;
  insert into public.economy_balances (actor_id, resource_id, balance)
    select v_actor_c, id, 0 from public.economy_resources;

  v_tx_id := gen_random_uuid();
  v_entries := jsonb_build_array(
    jsonb_build_object(
      'actor_id', v_actor_a,
      'resource_id', 'gems',
      'delta', 10,
      'kind', 'transfer'
    ),
    jsonb_build_object(
      'actor_id', v_actor_b,
      'resource_id', 'gems',
      'delta', 5,
      'kind', 'transfer'
    ),
    jsonb_build_object(
      'actor_id', v_actor_c,
      'resource_id', 'gems',
      'delta', -20,
      'kind', 'transfer'
    )
  );
  v_result := public.economy_post_tx(v_tx_id, v_entries);
  raise notice 'Unbalanced TX result (should fail): %', v_result;
end; $$;

-- Vérifier que le ledger n'a pas enregistré cette TX
select count(*) as ledger_count from public.economy_ledger;

-- 5) TEST 3 : TX insuffisant solde (doit REFUSER)
select 'TEST 3 : A essaie de dépenser 60 gems alors qu''il n''en a que 40 → DOIT REFUSER' as test;
do $$
declare
  v_actor_a uuid;
  v_actor_b uuid;
  v_tx_id uuid;
  v_result jsonb;
  v_entries jsonb;
begin
  select id into v_actor_a from public.economy_actors where type = 'player' and name = 'test_actor_a';
  select id into v_actor_b from public.economy_actors where type = 'player' and name = 'test_actor_b';

  v_tx_id := gen_random_uuid();
  v_entries := jsonb_build_array(
    jsonb_build_object(
      'actor_id', v_actor_a,
      'resource_id', 'gems',
      'delta', -60,
      'kind', 'transfer'
    ),
    jsonb_build_object(
      'actor_id', v_actor_b,
      'resource_id', 'gems',
      'delta', 60,
      'kind', 'transfer'
    )
  );
  v_result := public.economy_post_tx(v_tx_id, v_entries);
  raise notice 'Insufficient balance TX (should fail): %', v_result;
end; $$;

-- Vérifier que les balances n'ont pas changé
select ea.name, eb.resource_id, eb.balance
  from public.economy_balances eb
  join public.economy_actors ea on ea.id = eb.actor_id
  where ea.type = 'player' and ea.name in ('test_actor_a', 'test_actor_b')
  order by ea.name, eb.resource_id;

-- 6) Vérifier immuabilité du ledger (essayer de modifier)
select 'TEST 4 : Vérifier immuabilité (UPDATE ledger → doit ÉCHOUER)' as test;
do $$
begin
  update public.economy_ledger set delta = 999 where id = 1;
  raise exception 'ERROR: ledger was modified!';
exception when others then
  raise notice 'Good: ledger is immutable. Error: %', sqlerrm;
end; $$;

-- 7) Résumé final
select 'RÉSUMÉ' as test;
select
  ea.name,
  (select balance from public.economy_balances where actor_id = ea.id and resource_id = 'cash') as balance_cash,
  (select balance from public.economy_balances where actor_id = ea.id and resource_id = 'gems') as balance_gems
from public.economy_actors ea
where ea.type = 'player' and ea.name in ('test_actor_a', 'test_actor_b', 'test_actor_c')
order by ea.name;

select 'Ledger entries (all players)' as test;
select el.tx_id, ea.name, el.resource_id, el.delta, el.kind, el.created_at
  from public.economy_ledger el
  join public.economy_actors ea on ea.id = el.actor_id
  where ea.type = 'player' and ea.name like 'test_%'
  order by el.created_at;

select 'Tests finished ✓' as result;
