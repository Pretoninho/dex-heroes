-- ============================================================================
-- Dex Heroes — Tier RETAIL : acheter des gems AU COURS du marché
-- À coller APRÈS economy.sql + l2 + l3 + l4 + market_api + fees + market_order + l3b
-- ============================================================================
-- Le bouton « acheter des gems » du jeu devient un ordre Market plafonné sur le
-- tier retail. Le cash du jeu (hors-ledger) transite par un SOUS-ACTEUR dédié
-- « retail:<uid> » TOUJOURS remis à zéro → aucun risque pour le wallet Exchange
-- du joueur. Pas de frais de retrait (c'est un achat retail, pas un retrait).
-- ============================================================================

-- Autoriser un type d'acteur 'retail' (sous-acteur de passage)
do $$ declare c text; begin
  for c in select conname from pg_constraint where conrelid='public.economy_actors'::regclass and contype='c' loop
    execute 'alter table public.economy_actors drop constraint '||quote_ident(c);
  end loop;
end $$;
alter table public.economy_actors
  add constraint economy_actors_type_chk check (type in ('player','npc','system','retail'));

-- Config du tier retail (plafond par ordre, tunable)
insert into public.economy_config (key, value) values
  ('retail', jsonb_build_object('max_gems_per_order', 5000))
on conflict (key) do nothing;

-- Sous-acteur retail du joueur (créé une fois, toujours soldé à 0 entre les appels)
create or replace function public.economy_ensure_retail_actor()
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select id into v_id from public.economy_actors where type='retail' and user_id=auth.uid() limit 1;
  if v_id is null then
    insert into public.economy_actors (type, name, user_id)
      values ('retail', 'retail:'||auth.uid()::text, auth.uid()) returning id into v_id;
  end if;
  return v_id;
end; $$;
grant execute on function public.economy_ensure_retail_actor() to authenticated;

-- Acheter p_gems au cours, dans la limite du budget p_budget (cash du jeu).
-- Renvoie { success, gems, cost }. Le client applique : cash -= cost ; gems += gems.
create or replace function public.economy_retail_buy_gems(p_gems numeric, p_budget numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_r uuid; v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_cap numeric; v_cfg jsonb;
  v_gems numeric; v_cash numeric;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  p_gems := floor(coalesce(p_gems,0)); p_budget := coalesce(p_budget,0);
  if p_gems <= 0 then return jsonb_build_object('success',false,'error','invalid amount'); end if;
  if p_budget <= 0 then return jsonb_build_object('success',false,'error','no budget'); end if;

  select value into v_cfg from public.economy_config where key='retail';
  v_cap := coalesce((v_cfg->>'max_gems_per_order')::numeric, 5000);
  if p_gems > v_cap then p_gems := v_cap; end if;

  v_r := public.economy_ensure_retail_actor();   -- solde garanti à 0 (atomicité)

  -- 1) Faucet du budget (cash du jeu) vers le sous-acteur
  perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('actor_id',v_sys,'resource_id','cash','delta',-p_budget,'kind','deposit'),
    jsonb_build_object('actor_id',v_r,  'resource_id','cash','delta', p_budget,'kind','deposit')
  ));

  -- 2) Achat Market au cours (dépense le cash du sous-acteur, plafonné par le solde)
  perform public.economy_market_order_as(v_r, 'buy', p_gems);

  -- 3) Le sous-acteur (parti de 0) détient : gems achetés + cash non dépensé
  select coalesce(balance,0) into v_gems from public.economy_balances where actor_id=v_r and resource_id='gems';
  select coalesce(balance,0) into v_cash from public.economy_balances where actor_id=v_r and resource_id='cash';

  -- 4) Tout renvoyer au jeu (SANS frais de retrait), sous-acteur ramené à 0
  if v_gems > 0 then
    perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id',v_r,  'resource_id','gems','delta',-v_gems,'kind','withdraw'),
      jsonb_build_object('actor_id',v_sys,'resource_id','gems','delta', v_gems,'kind','withdraw')
    ));
  end if;
  if v_cash > 0 then
    perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id',v_r,  'resource_id','cash','delta',-v_cash,'kind','withdraw'),
      jsonb_build_object('actor_id',v_sys,'resource_id','cash','delta', v_cash,'kind','withdraw')
    ));
  end if;

  if v_gems <= 0 then return jsonb_build_object('success',false,'error','no liquidity'); end if;
  return jsonb_build_object('success',true, 'gems',v_gems, 'cost', p_budget - v_cash);
end; $$;
grant execute on function public.economy_retail_buy_gems(numeric, numeric) to authenticated;
