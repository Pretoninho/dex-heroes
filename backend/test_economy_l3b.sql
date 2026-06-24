-- ============================================================================
-- Dex Heroes — Tests L3b (NPC réactif)
-- À coller APRÈS economy_l3b.sql
-- ============================================================================
-- Vérifie : (1) le tick tourne 12× sans erreur, (2) la CONSERVATION reste à 0
-- (le test prioritaire pour un NPC : il ne crée/détruit rien hors SYSTÈME),
-- (3) le cours a BOUGÉ (le réactif est bien actif).
-- Note : les 12 ticks tournent dans une seule transaction → même horodatage
-- pour les snapshots (en prod, pg_cron = 1 tx/minute, horodatages distincts).
-- ============================================================================

do $$
declare i int; v jsonb;
begin
  for i in 1..12 loop v := public.economy_tick_npcs(); end loop;
  raise notice 'Dernier tick : %', v;
end $$;

-- (2) Conservation globale : somme de tous les soldes = 0 par ressource
do $$
declare r record;
begin
  for r in select resource_id, round(sum(balance),6) as tot from public.economy_balances group by resource_id loop
    if r.tot != 0 then raise exception 'CONSERVATION VIOLÉE : % = % (attendu 0)', r.resource_id, r.tot; end if;
    raise notice '✓ conservation % = 0', r.resource_id;
  end loop;
end $$;

-- (3) Le cours a bougé (amplitude > 0 sur l'historique récent)
do $$
declare v_hi numeric; v_lo numeric; v_n int;
begin
  select max(price), min(price), count(*) into v_hi, v_lo, v_n
  from (select price from public.economy_price_history order by captured_at desc, id desc limit 30) s;
  raise notice 'Historique récent : % points · haut % · bas %', v_n, v_hi, v_lo;
  if coalesce(v_hi,0) = coalesce(v_lo,0) then
    raise exception 'Le cours n''a pas bougé — le réactif semble inactif';
  end if;
  raise notice '✓ le cours bouge (amplitude %)', round(v_hi - v_lo, 4);
end $$;

-- Les deux NPC existent et ont des soldes
select ea.name, ea.policy->>'role' as role,
  (select balance from public.economy_balances where actor_id=ea.id and resource_id='gems') as gems,
  (select balance from public.economy_balances where actor_id=ea.id and resource_id='cash') as cash
from public.economy_actors ea where ea.type='npc' order by ea.name;

select 'Tests L3b finished ✓ (conservation OK, cours animé)' as result;
