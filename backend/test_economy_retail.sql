-- ============================================================================
-- Dex Heroes — Test du tier RETAIL (achat de gems au cours)
-- À coller APRÈS economy_retail.sql
-- ============================================================================
-- La fonction publique exige auth.uid() ; ici on teste le MÉCANISME sur un
-- sous-acteur retail de test (faucet → market buy → sink) : conservation OK +
-- sous-acteur ramené à 0 (donc aucun risque pour le wallet d'un vrai joueur).
-- ============================================================================

do $$
declare
  v_r uuid; v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_budget numeric := 100000; v_gems numeric; v_cash numeric; v_sum numeric;
begin
  perform public.economy_tick_npcs();   -- garantir de la liquidité (le MM poste ses asks)

  insert into public.economy_actors(type,name) values('retail','retail_test_'||gen_random_uuid()::text) returning id into v_r;

  -- faucet budget
  perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id',v_sys,'resource_id','cash','delta',-v_budget,'kind','deposit'),
    jsonb_build_object('actor_id',v_r,  'resource_id','cash','delta', v_budget,'kind','deposit')));

  -- achat market au cours
  perform public.economy_market_order_as(v_r,'buy',100);

  select coalesce(balance,0) into v_gems from public.economy_balances where actor_id=v_r and resource_id='gems';
  select coalesce(balance,0) into v_cash from public.economy_balances where actor_id=v_r and resource_id='cash';
  raise notice 'Acheté % gems · cash restant % · cost %', v_gems, v_cash, v_budget - v_cash;
  if v_gems <= 0 then raise exception 'FAIL: aucun gem acheté (liquidité ?)'; end if;

  -- sink tout (retour au jeu, sous-acteur ramené à 0)
  perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id',v_r,  'resource_id','gems','delta',-v_gems,'kind','withdraw'),
    jsonb_build_object('actor_id',v_sys,'resource_id','gems','delta', v_gems,'kind','withdraw')));
  if v_cash > 0 then
    perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id',v_r,  'resource_id','cash','delta',-v_cash,'kind','withdraw'),
      jsonb_build_object('actor_id',v_sys,'resource_id','cash','delta', v_cash,'kind','withdraw')));
  end if;

  select coalesce(sum(balance),0) into v_sum from public.economy_balances where actor_id=v_r;
  if v_sum != 0 then raise exception 'FAIL: sous-acteur non soldé (% restant)', v_sum; end if;
  raise notice '✓ achat retail OK · sous-acteur soldé à 0';
end $$;

-- Conservation globale (l'invariant clé)
do $$ declare r record; begin
  for r in select resource_id, round(sum(balance),6) as tot from public.economy_balances group by resource_id loop
    if r.tot != 0 then raise exception 'CONSERVATION VIOLÉE : % = %', r.resource_id, r.tot; end if;
    raise notice '✓ conservation % = 0', r.resource_id;
  end loop;
end $$;

select 'Tests retail finished ✓' as result;
