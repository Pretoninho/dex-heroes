-- ============================================================================
-- Dex Heroes — L4 : Régime de marché émergent (global, stable)
-- À coller dans Supabase APRÈS economy.sql + economy_l2.sql + economy_l3.sql
-- ============================================================================
-- Principe : le régime ne TIRE rien au hasard. Il LIT le marché interne :
--   tendance (dérivée du cours) + volatilité + volume → 1 des 5 régimes.
-- Global (un seul pour tous), recalculé à chaque tick, mais STABLE grâce à
-- une hystérésis (un régime tient un minimum de temps + confirmation sur
-- plusieurs ticks) → il ne change PAS toutes les minutes.
-- Pure lecture : L4 n'émet aucun tx → conservation garantie par construction.
-- ============================================================================

-- 1) Config (seuils tunables sans toucher au code) ---------------------------
create table if not exists public.economy_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.economy_config enable row level security;
drop policy if exists "config_read_all" on public.economy_config;
create policy "config_read_all" on public.economy_config for select using (true);

insert into public.economy_config (key, value) values
  ('regime', jsonb_build_object(
    'window', 10,            -- nb de points d'historique analysés
    'min_points', 5,         -- en-dessous : régime neutre (CRABE)
    'trend_soft', 0.02,      -- |tendance| pour BULL/BEAR
    'trend_strong', 0.08,    -- |tendance| pour HYPE/CRASH
    'normal_hold_sec', 600,  -- un régime "normal" tient >= 10 min avant de changer
    'extreme_hold_sec', 120, -- CRASH/HYPE peuvent interrompre plus vite (2 min)
    'confirm_normal', 3,     -- candidat confirmé sur 3 ticks consécutifs
    'confirm_extreme', 2     -- CRASH/HYPE confirmés sur 2 ticks
  ))
on conflict (key) do nothing;

-- 2) Historique de prix (snapshot par tick) ----------------------------------
-- Donne des points RÉGULIERS (1/minute) pour une tendance propre, même si les
-- trades sont sporadiques.
create table if not exists public.economy_price_history (
  id bigserial primary key,
  price numeric not null,
  volume numeric not null default 0,
  captured_at timestamptz not null default now()
);
alter table public.economy_price_history enable row level security;
drop policy if exists "pricehist_read_all" on public.economy_price_history;
create policy "pricehist_read_all" on public.economy_price_history for select using (true);
create index if not exists idx_pricehist_time on public.economy_price_history (captured_at desc);

-- 3) État du régime (singleton global) ---------------------------------------
create table if not exists public.economy_regime_state (
  id text primary key default 'global',
  regime text not null default 'CRABE',
  confidence numeric not null default 0,
  trend numeric not null default 0,
  volatility numeric not null default 0,
  volume numeric not null default 0,
  candidate text,                       -- régime en attente de confirmation
  candidate_count integer not null default 0,
  since timestamptz not null default now(),     -- depuis quand le régime courant tient
  updated_at timestamptz not null default now()
);
alter table public.economy_regime_state enable row level security;
drop policy if exists "regime_read_all" on public.economy_regime_state;
create policy "regime_read_all" on public.economy_regime_state for select using (true);

insert into public.economy_regime_state (id, regime) values ('global', 'CRABE')
  on conflict (id) do nothing;

-- 4) Classer l'état du marché en un régime (pure lecture, déterministe) -------
-- Renvoie un candidat (le régime que le marché "dit" maintenant) + métriques.
create or replace function public.economy_classify_market()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_cfg jsonb;
  v_window integer; v_min_points integer; v_soft numeric; v_strong numeric;
  v_n integer; v_first numeric; v_last numeric;
  v_trend numeric := 0; v_volatility numeric := 0; v_volume numeric := 0;
  v_candidate text; v_confidence numeric := 0;
begin
  select value into v_cfg from public.economy_config where key = 'regime';
  v_window := coalesce((v_cfg->>'window')::int, 10);
  v_min_points := coalesce((v_cfg->>'min_points')::int, 5);
  v_soft := coalesce((v_cfg->>'trend_soft')::numeric, 0.02);
  v_strong := coalesce((v_cfg->>'trend_strong')::numeric, 0.08);

  -- Fenêtre des derniers points
  with w as (
    select price, volume, captured_at
    from public.economy_price_history
    order by captured_at desc
    limit v_window
  )
  select count(*),
         (select price from w order by captured_at asc  limit 1),
         (select price from w order by captured_at desc limit 1),
         coalesce(avg(volume), 0)
  into v_n, v_first, v_last, v_volume
  from w;

  -- Pas assez de données → régime neutre, pas de faux signal
  if v_n < v_min_points or coalesce(v_first,0) = 0 then
    return jsonb_build_object('candidate','CRABE','confidence',0,'trend',0,'volatility',0,'volume',coalesce(v_volume,0),'points',coalesce(v_n,0));
  end if;

  v_trend := (v_last - v_first) / v_first;

  -- Volatilité = écart-type des rendements point à point
  select coalesce(stddev_pop(ret), 0) into v_volatility from (
    select (price - lag(price) over (order by captured_at))
           / nullif(lag(price) over (order by captured_at), 0) as ret
    from (select price, captured_at from public.economy_price_history
          order by captured_at desc limit v_window) s
  ) r where ret is not null;

  -- Classement déterministe
  if v_trend >= v_strong and v_volume > 0 then
    v_candidate := 'HYPE';
  elsif v_trend <= -v_strong and v_volume > 0 then
    v_candidate := 'CRASH';
  elsif v_trend >= v_soft then
    v_candidate := 'BULL';
  elsif v_trend <= -v_soft then
    v_candidate := 'BEAR';
  else
    v_candidate := 'CRABE';
  end if;

  v_confidence := least(1.0, abs(v_trend) / v_strong);

  return jsonb_build_object(
    'candidate', v_candidate, 'confidence', round(v_confidence,3),
    'trend', round(v_trend,4), 'volatility', round(v_volatility,4),
    'volume', v_volume, 'points', v_n
  );
end; $$;

grant execute on function public.economy_classify_market() to authenticated;

-- 5) Mettre à jour le régime avec HYSTÉRÉSIS (la stabilité) -------------------
-- Le régime ne change QUE si le candidat :
--   (a) est confirmé sur N ticks consécutifs, ET
--   (b) le régime courant a tenu au moins son "hold" minimum.
-- CRASH/HYPE = évènements : hold plus court + confirmation plus rapide.
create or replace function public.economy_update_regime()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_cfg jsonb;
  v_class jsonb;
  v_candidate text;
  v_state public.economy_regime_state;
  v_is_extreme boolean;
  v_hold_sec integer; v_confirm integer;
  v_age_sec numeric;
  v_new_count integer;
  v_switch boolean := false;
begin
  select value into v_cfg from public.economy_config where key = 'regime';
  v_class := public.economy_classify_market();
  v_candidate := v_class->>'candidate';

  select * into v_state from public.economy_regime_state where id = 'global' for update;

  -- Le marché confirme le régime courant → on efface toute candidature en attente
  if v_candidate = v_state.regime then
    update public.economy_regime_state set
      candidate = null, candidate_count = 0,
      confidence = (v_class->>'confidence')::numeric,
      trend = (v_class->>'trend')::numeric,
      volatility = (v_class->>'volatility')::numeric,
      volume = (v_class->>'volume')::numeric,
      updated_at = now()
    where id = 'global';
    return jsonb_build_object('regime', v_state.regime, 'changed', false, 'candidate', v_candidate, 'class', v_class);
  end if;

  -- Sinon : un candidat différent. Compter ses ticks consécutifs.
  if v_candidate = v_state.candidate then
    v_new_count := v_state.candidate_count + 1;
  else
    v_new_count := 1;
  end if;

  v_is_extreme := v_candidate in ('CRASH', 'HYPE');
  v_hold_sec := case when v_is_extreme then coalesce((v_cfg->>'extreme_hold_sec')::int, 120)
                     else coalesce((v_cfg->>'normal_hold_sec')::int, 600) end;
  v_confirm := case when v_is_extreme then coalesce((v_cfg->>'confirm_extreme')::int, 2)
                    else coalesce((v_cfg->>'confirm_normal')::int, 3) end;

  v_age_sec := extract(epoch from (now() - v_state.since));

  -- Switch autorisé si confirmé ET le régime courant a assez tenu
  if v_new_count >= v_confirm and v_age_sec >= v_hold_sec then
    v_switch := true;
  end if;

  if v_switch then
    update public.economy_regime_state set
      regime = v_candidate, since = now(),
      candidate = null, candidate_count = 0,
      confidence = (v_class->>'confidence')::numeric,
      trend = (v_class->>'trend')::numeric,
      volatility = (v_class->>'volatility')::numeric,
      volume = (v_class->>'volume')::numeric,
      updated_at = now()
    where id = 'global';
    return jsonb_build_object('regime', v_candidate, 'changed', true, 'class', v_class);
  else
    update public.economy_regime_state set
      candidate = v_candidate, candidate_count = v_new_count,
      trend = (v_class->>'trend')::numeric,
      volatility = (v_class->>'volatility')::numeric,
      volume = (v_class->>'volume')::numeric,
      updated_at = now()
    where id = 'global';
    return jsonb_build_object('regime', v_state.regime, 'changed', false,
      'candidate', v_candidate, 'candidate_count', v_new_count, 'class', v_class);
  end if;
end; $$;

grant execute on function public.economy_update_regime() to authenticated;

-- 6) Lire le régime courant (pour le client) ---------------------------------
create or replace function public.economy_get_regime()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v public.economy_regime_state;
begin
  select * into v from public.economy_regime_state where id = 'global';
  return jsonb_build_object(
    'regime', v.regime, 'confidence', v.confidence,
    'trend', v.trend, 'volatility', v.volatility, 'volume', v.volume,
    'since', v.since
  );
end; $$;

grant execute on function public.economy_get_regime() to authenticated;

-- 7) Intégrer au tick : snapshot d'historique + maj du régime ----------------
-- Redéfinit economy_tick_npcs (L3) pour ajouter, après le matching :
--   - un point d'historique de prix
--   - la réévaluation du régime (avec hystérésis)
create or replace function public.economy_tick_npcs()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_npc public.economy_actors;
  v_ref numeric; v_spread numeric; v_depth numeric; v_anchor numeric;
  v_buy_price numeric; v_sell_price numeric; v_index_price numeric;
  v_count integer := 0; v_regime jsonb;
begin
  perform public.economy_ensure_market_maker();
  select price into v_index_price from public.economy_price_index where id = 'gems_cash';

  for v_npc in select * from public.economy_actors where type = 'npc' loop
    if v_npc.policy->>'role' = 'market_maker' then
      v_spread := coalesce((v_npc.policy->>'spread')::numeric, 0.04);
      v_depth  := coalesce((v_npc.policy->>'depth')::numeric, 50);
      v_anchor := coalesce((v_npc.policy->>'anchor')::numeric, 100);
      v_ref := case when coalesce(v_index_price,0) > 0 then v_index_price else v_anchor end;
      v_buy_price  := round(v_ref * (1 - v_spread), 4);
      v_sell_price := round(v_ref * (1 + v_spread), 4);
      perform public.economy_cancel_all_orders(v_npc.id);
      perform public.economy_place_order_as(v_npc.id, 'buy',  v_depth, v_buy_price);
      perform public.economy_place_order_as(v_npc.id, 'sell', v_depth, v_sell_price);
      v_count := v_count + 1;
    end if;
  end loop;

  perform public.economy_match_orders();

  -- Snapshot du cours dans l'historique (pour la tendance du régime)
  select price into v_index_price from public.economy_price_index where id = 'gems_cash';
  insert into public.economy_price_history (price, volume)
    select v_index_price, volume_recent from public.economy_price_index where id = 'gems_cash';

  -- Réévaluer le régime (hystérésis incluse)
  v_regime := public.economy_update_regime();

  return jsonb_build_object('npcs_ticked', v_count, 'ref_price', v_ref, 'regime', v_regime);
end; $$;

grant execute on function public.economy_tick_npcs() to authenticated;
