-- ============================================================================
-- Dex Heroes — Tests L4 (Régime émergent)
-- À coller dans Supabase APRÈS economy.sql + l2 + l3 + economy_l4.sql
-- ============================================================================
-- Vérifie : classification déterministe (BULL/BEAR/CRASH/CRABE/HYPE),
-- pas de faux signal sans données, et HYSTÉRÉSIS (le régime ne change pas
-- toutes les minutes : confirmation sur N ticks + durée de maintien minimale).
-- ============================================================================

-- Helper local : remplit l'historique avec une série de prix.
-- (défini en bloc do à chaque section pour rester auto-contenu)

-- ============ TEST 1 : classification ============
do $$
declare v_class jsonb; i int;
begin
  -- BULL : montée douce 100 -> 104 (+4%, entre soft 2% et strong 8%)
  delete from public.economy_price_history;
  for i in 1..10 loop
    insert into public.economy_price_history (price, volume, captured_at)
      values (100 + (i-1)*0.45, 5, now() - (10-i) * interval '6 second');
  end loop;
  v_class := public.economy_classify_market();
  raise notice 'BULL? %', v_class;
  if v_class->>'candidate' != 'BULL' then raise exception 'TEST1 FAIL: attendu BULL, obtenu %', v_class->>'candidate'; end if;

  -- BEAR : descente douce 100 -> 96 (-4%)
  delete from public.economy_price_history;
  for i in 1..10 loop
    insert into public.economy_price_history (price, volume, captured_at)
      values (100 - (i-1)*0.45, 5, now() - (10-i) * interval '6 second');
  end loop;
  v_class := public.economy_classify_market();
  raise notice 'BEAR? %', v_class;
  if v_class->>'candidate' != 'BEAR' then raise exception 'TEST1 FAIL: attendu BEAR, obtenu %', v_class->>'candidate'; end if;

  -- CRASH : chute 100 -> 86 (-14%) avec volume > 0
  delete from public.economy_price_history;
  for i in 1..10 loop
    insert into public.economy_price_history (price, volume, captured_at)
      values (100 - (i-1)*1.55, 20, now() - (10-i) * interval '6 second');
  end loop;
  v_class := public.economy_classify_market();
  raise notice 'CRASH? %', v_class;
  if v_class->>'candidate' != 'CRASH' then raise exception 'TEST1 FAIL: attendu CRASH, obtenu %', v_class->>'candidate'; end if;

  -- HYPE : flambée 100 -> 114 (+14%) avec volume > 0
  delete from public.economy_price_history;
  for i in 1..10 loop
    insert into public.economy_price_history (price, volume, captured_at)
      values (100 + (i-1)*1.55, 20, now() - (10-i) * interval '6 second');
  end loop;
  v_class := public.economy_classify_market();
  raise notice 'HYPE? %', v_class;
  if v_class->>'candidate' != 'HYPE' then raise exception 'TEST1 FAIL: attendu HYPE, obtenu %', v_class->>'candidate'; end if;

  -- CRABE : plat 100
  delete from public.economy_price_history;
  for i in 1..10 loop
    insert into public.economy_price_history (price, volume, captured_at)
      values (100, 5, now() - (10-i) * interval '6 second');
  end loop;
  v_class := public.economy_classify_market();
  raise notice 'CRABE? %', v_class;
  if v_class->>'candidate' != 'CRABE' then raise exception 'TEST1 FAIL: attendu CRABE, obtenu %', v_class->>'candidate'; end if;

  raise notice '✓ TEST 1 OK : les 5 régimes se classent correctement';
end; $$;

-- ============ TEST 2 : pas de faux signal sans données ============
do $$
declare v_class jsonb;
begin
  delete from public.economy_price_history;  -- 0 point
  v_class := public.economy_classify_market();
  raise notice 'Sans données : %', v_class;
  if v_class->>'candidate' != 'CRABE' then raise exception 'TEST2 FAIL: marché vide doit donner CRABE, obtenu %', v_class->>'candidate'; end if;
  raise notice '✓ TEST 2 OK : marché vide → CRABE (pas de CRASH fantôme)';
end; $$;

-- ============ TEST 3 : déterminisme ============
do $$
declare v1 jsonb; v2 jsonb; i int;
begin
  delete from public.economy_price_history;
  for i in 1..10 loop
    insert into public.economy_price_history (price, volume, captured_at)
      values (100 + (i-1)*0.45, 5, now() - (10-i) * interval '6 second');
  end loop;
  v1 := public.economy_classify_market();
  v2 := public.economy_classify_market();
  if v1->>'candidate' != v2->>'candidate' or v1->>'trend' != v2->>'trend' then
    raise exception 'TEST3 FAIL: non déterministe (% vs %)', v1, v2;
  end if;
  raise notice '✓ TEST 3 OK : déterministe (% == %)', v1->>'candidate', v2->>'candidate';
end; $$;

-- ============ TEST 4 : HYSTÉRÉSIS — un signal isolé ne flippe pas ============
do $$
declare v_upd jsonb; i int;
begin
  -- Mettre le régime courant à BULL, ancien (hold satisfait), aucune candidature
  update public.economy_regime_state set regime='BULL', since = now() - interval '1 hour',
    candidate=null, candidate_count=0 where id='global';

  -- Injecter un signal CRASH
  delete from public.economy_price_history;
  for i in 1..10 loop
    insert into public.economy_price_history (price, volume, captured_at)
      values (100 - (i-1)*1.55, 20, now() - (10-i) * interval '6 second');
  end loop;

  -- 1er tick : CRASH détecté mais NON confirmé (confirm_extreme=2) → reste BULL
  v_upd := public.economy_update_regime();
  raise notice 'Tick 1 (CRASH détecté, 1ère fois) : %', v_upd;
  if (v_upd->>'changed')::boolean then raise exception 'TEST4 FAIL: a flippé au 1er signal !'; end if;
  if v_upd->>'regime' != 'BULL' then raise exception 'TEST4 FAIL: devrait rester BULL, est %', v_upd->>'regime'; end if;

  -- 2e tick : confirmé (count=2) ET hold satisfait → bascule CRASH
  v_upd := public.economy_update_regime();
  raise notice 'Tick 2 (CRASH confirmé) : %', v_upd;
  if not (v_upd->>'changed')::boolean then raise exception 'TEST4 FAIL: aurait dû basculer en CRASH'; end if;
  if v_upd->>'regime' != 'CRASH' then raise exception 'TEST4 FAIL: devrait être CRASH, est %', v_upd->>'regime'; end if;

  raise notice '✓ TEST 4 OK : 1 signal isolé ne change rien ; il faut confirmation';
end; $$;

-- ============ TEST 5 : HYSTÉRÉSIS — un régime frais ne change pas vite ============
do $$
declare v_upd jsonb; i int;
begin
  -- Régime CRABE qui vient JUSTE de commencer (hold normal = 600s NON satisfait)
  update public.economy_regime_state set regime='CRABE', since = now(),
    candidate=null, candidate_count=0 where id='global';

  -- Signal BULL soutenu
  delete from public.economy_price_history;
  for i in 1..10 loop
    insert into public.economy_price_history (price, volume, captured_at)
      values (100 + (i-1)*0.45, 5, now() - (10-i) * interval '6 second');
  end loop;

  -- Même confirmé sur 3+ ticks, le hold de 600s n'est pas écoulé → reste CRABE
  for i in 1..5 loop
    v_upd := public.economy_update_regime();
  end loop;
  raise notice 'Après 5 ticks BULL sur régime frais : %', v_upd;
  if (v_upd->>'changed')::boolean or v_upd->>'regime' != 'CRABE' then
    raise exception 'TEST5 FAIL: a changé alors que le régime venait de commencer (%)' , v_upd->>'regime';
  end if;
  raise notice '✓ TEST 5 OK : un régime récent tient (pas de changement toutes les minutes)';
end; $$;

-- Conservation : L4 ne fait que lire → la somme des soldes reste 0
do $$
declare v_r record;
begin
  for v_r in select resource_id, sum(balance) as total_net from public.economy_balances group by resource_id loop
    if v_r.total_net != 0 then raise exception 'CONSERVATION VIOLÉE par L4 (impossible) : % = %', v_r.resource_id, v_r.total_net; end if;
  end loop;
  raise notice '✓ Conservation intacte (L4 = lecture pure)';
end; $$;

-- Remettre un état neutre propre pour la suite
update public.economy_regime_state set regime='CRABE', since=now(), candidate=null, candidate_count=0 where id='global';
delete from public.economy_price_history;

select 'Tests L4 finished ✓ (classification + déterminisme + hystérésis)' as result;
