-- ============================================================================
-- Dex Heroes — Tests L1 (Ledger + Acteurs)
-- À coller dans Supabase APRÈS economy.sql
-- ============================================================================
-- Ré-exécutable : acteurs neufs à chaque passe, assertions qui lèvent si faux.
-- ============================================================================

do $$
declare
  v_a uuid; v_b uuid;
  v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_res jsonb;
  v_a_gems numeric; v_b_gems numeric;
  v_ledger_before bigint; v_ledger_after bigint;
begin
  -- Acteurs neufs
  insert into public.economy_actors (type, name) values ('player', 'l1_a_' || gen_random_uuid()::text) returning id into v_a;
  insert into public.economy_actors (type, name) values ('player', 'l1_b_' || gen_random_uuid()::text) returning id into v_b;

  -- TEST 1 : faucet (SYSTÈME -50 gems, A +50) → doit RÉUSSIR
  v_res := public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id', v_sys, 'resource_id', 'gems', 'delta', -50, 'kind', 'production'),
    jsonb_build_object('actor_id', v_a,   'resource_id', 'gems', 'delta',  50, 'kind', 'production')
  ));
  raise notice 'TEST 1 faucet : %', v_res;
  if (v_res->>'success')::boolean is not true then raise exception 'TEST 1 FAIL: faucet rejeté'; end if;

  -- TEST 2 : transfert équilibré (A -10, B +10) → doit RÉUSSIR
  v_res := public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id', v_a, 'resource_id', 'gems', 'delta', -10, 'kind', 'transfer'),
    jsonb_build_object('actor_id', v_b, 'resource_id', 'gems', 'delta',  10, 'kind', 'transfer')
  ));
  raise notice 'TEST 2 transfert : %', v_res;
  if (v_res->>'success')::boolean is not true then raise exception 'TEST 2 FAIL: transfert rejeté'; end if;

  -- Vérifier soldes : A=40, B=10
  select balance into v_a_gems from public.economy_balances where actor_id = v_a and resource_id = 'gems';
  select balance into v_b_gems from public.economy_balances where actor_id = v_b and resource_id = 'gems';
  if v_a_gems != 40 then raise exception 'TEST 2 FAIL: A gems = % (attendu 40)', v_a_gems; end if;
  if v_b_gems != 10 then raise exception 'TEST 2 FAIL: B gems = % (attendu 10)', v_b_gems; end if;

  -- TEST 3 : déséquilibrée (A -10, B +5 → total -5) → doit ÉCHOUER
  v_res := public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id', v_a, 'resource_id', 'gems', 'delta', -10, 'kind', 'transfer'),
    jsonb_build_object('actor_id', v_b, 'resource_id', 'gems', 'delta',   5, 'kind', 'transfer')
  ));
  raise notice 'TEST 3 déséquilibrée (doit échouer) : %', v_res;
  if (v_res->>'success')::boolean is true then raise exception 'TEST 3 FAIL: déséquilibre accepté !'; end if;

  -- TEST 4 : solde insuffisant (A a 40, veut envoyer 60) → doit ÉCHOUER
  v_res := public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id', v_a, 'resource_id', 'gems', 'delta', -60, 'kind', 'transfer'),
    jsonb_build_object('actor_id', v_b, 'resource_id', 'gems', 'delta',  60, 'kind', 'transfer')
  ));
  raise notice 'TEST 4 solde insuffisant (doit échouer) : %', v_res;
  if (v_res->>'success')::boolean is true then raise exception 'TEST 4 FAIL: dépassement de solde accepté !'; end if;

  -- Vérifier que TEST 3 et 4 n'ont rien changé : A toujours 40, B toujours 10
  select balance into v_a_gems from public.economy_balances where actor_id = v_a and resource_id = 'gems';
  select balance into v_b_gems from public.economy_balances where actor_id = v_b and resource_id = 'gems';
  if v_a_gems != 40 or v_b_gems != 10 then raise exception 'FAIL: TX rejetées ont muté les soldes (A=%, B=%)', v_a_gems, v_b_gems; end if;

  raise notice '✓ ASSERTIONS L1 OK';
end; $$;

-- TEST 5 : immuabilité du ledger (UPDATE → doit ÉCHOUER)
do $$
begin
  update public.economy_ledger set delta = 999 where id = (select min(id) from public.economy_ledger);
  raise exception 'TEST 5 FAIL: le ledger a été modifié !';
exception
  when others then
    if sqlerrm like '%immutable%' then
      raise notice '✓ TEST 5 OK : ledger immuable (%))', sqlerrm;
    else
      raise; -- une autre erreur : on la remonte
    end if;
end; $$;

select 'Tests L1 finished ✓ (assertions passées)' as result;
