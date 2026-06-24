-- ============================================================================
-- Dex Heroes — API marché pour l'UI exchange (ticker UTC + lectures publiques)
-- À coller APRÈS economy.sql + l2 + l3 + economy_l4.sql
-- ============================================================================
-- Heure du jeu = UTC. La variation se calcule depuis 00:00 UTC du jour courant
-- (le "cours d'ouverture" = 1er snapshot d'historique après minuit UTC).
-- ============================================================================

-- Ticker : prix courant + variation depuis 00:00 UTC + régime (NOM + métriques)
create or replace function public.economy_get_ticker()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_price numeric; v_open numeric; v_change numeric := 0;
  v_high numeric; v_low numeric;
  v_reg public.economy_regime_state;
  v_day_start timestamp := date_trunc('day', (now() at time zone 'UTC'));  -- minuit UTC (naïf)
begin
  select price into v_price from public.economy_price_index where id = 'gems_cash';

  -- Cours d'ouverture = 1er snapshot du jour (>= minuit UTC)
  select price into v_open from public.economy_price_history
    where (captured_at at time zone 'UTC') >= v_day_start
    order by captured_at asc limit 1;
  if coalesce(v_open, 0) = 0 then v_open := v_price; end if;

  -- Plus haut / plus bas du jour
  select max(price), min(price) into v_high, v_low from public.economy_price_history
    where (captured_at at time zone 'UTC') >= v_day_start;

  if coalesce(v_open, 0) > 0 then v_change := (coalesce(v_price,0) - v_open) / v_open; end if;

  select * into v_reg from public.economy_regime_state where id = 'global';

  return jsonb_build_object(
    'price',       coalesce(v_price, 0),
    'open',        coalesce(v_open, 0),
    'high',        coalesce(v_high, v_price, 0),
    'low',         coalesce(v_low, v_price, 0),
    'change_pct',  round(coalesce(v_change, 0) * 100, 2),
    'regime',      coalesce(v_reg.regime, 'CRABE'),
    'trend',       coalesce(v_reg.trend, 0),
    'confidence',  coalesce(v_reg.confidence, 0),
    'utc_now',     to_char((now() at time zone 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
end; $$;

-- Lectures publiques (le marché est visible même déconnecté) : grant à anon
grant execute on function public.economy_get_ticker() to authenticated, anon;
grant execute on function public.economy_orderbook()  to anon;
grant execute on function public.economy_get_price()  to anon;
grant execute on function public.economy_get_regime() to anon;

-- ============================================================================
-- Pont jeu <-> marché (ledger) + lectures perso
-- ============================================================================

-- Déposer du jeu VERS le marché : faucet dans le solde économie du joueur.
-- (Le client déduit d'autant l'état local du jeu.) Plafonné.
create or replace function public.economy_deposit(d_gems numeric, d_cash numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid; v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_entries jsonb := '[]'::jsonb; v_res jsonb;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  d_gems := coalesce(d_gems, 0); d_cash := coalesce(d_cash, 0);
  if d_gems < 0 or d_cash < 0 then raise exception 'negative amount'; end if;
  if d_gems > 1e9 or d_cash > 1e15 then raise exception 'deposit too large'; end if;
  if d_gems = 0 and d_cash = 0 then return jsonb_build_object('success', false, 'error', 'empty'); end if;

  v_actor := public.economy_ensure_player();
  if d_gems > 0 then
    v_entries := v_entries
      || jsonb_build_object('actor_id', v_sys,   'resource_id', 'gems', 'delta', -d_gems, 'kind', 'deposit')
      || jsonb_build_object('actor_id', v_actor, 'resource_id', 'gems', 'delta',  d_gems, 'kind', 'deposit');
  end if;
  if d_cash > 0 then
    v_entries := v_entries
      || jsonb_build_object('actor_id', v_sys,   'resource_id', 'cash', 'delta', -d_cash, 'kind', 'deposit')
      || jsonb_build_object('actor_id', v_actor, 'resource_id', 'cash', 'delta',  d_cash, 'kind', 'deposit');
  end if;

  v_res := public.economy_post_tx(gen_random_uuid(), v_entries);
  return v_res;
end; $$;
grant execute on function public.economy_deposit(numeric, numeric) to authenticated;

-- Retirer du marché VERS le jeu : sink du solde économie (le client recrédite le jeu).
create or replace function public.economy_withdraw(w_gems numeric, w_cash numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid; v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_entries jsonb := '[]'::jsonb; v_res jsonb;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  w_gems := coalesce(w_gems, 0); w_cash := coalesce(w_cash, 0);
  if w_gems < 0 or w_cash < 0 then raise exception 'negative amount'; end if;
  if w_gems = 0 and w_cash = 0 then return jsonb_build_object('success', false, 'error', 'empty'); end if;

  v_actor := public.economy_ensure_player();
  if w_gems > 0 then
    v_entries := v_entries
      || jsonb_build_object('actor_id', v_actor, 'resource_id', 'gems', 'delta', -w_gems, 'kind', 'withdraw')
      || jsonb_build_object('actor_id', v_sys,   'resource_id', 'gems', 'delta',  w_gems, 'kind', 'withdraw');
  end if;
  if w_cash > 0 then
    v_entries := v_entries
      || jsonb_build_object('actor_id', v_actor, 'resource_id', 'cash', 'delta', -w_cash, 'kind', 'withdraw')
      || jsonb_build_object('actor_id', v_sys,   'resource_id', 'cash', 'delta',  w_cash, 'kind', 'withdraw');
  end if;

  v_res := public.economy_post_tx(gen_random_uuid(), v_entries);  -- refuse si solde insuffisant
  return v_res;
end; $$;
grant execute on function public.economy_withdraw(numeric, numeric) to authenticated;

-- Mon solde marché (gems + cash) — RLS via auth.uid()
create or replace function public.economy_my_balances()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid; v_gems numeric; v_cash numeric;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  v_actor := public.economy_ensure_player();
  select balance into v_gems from public.economy_balances where actor_id = v_actor and resource_id = 'gems';
  select balance into v_cash from public.economy_balances where actor_id = v_actor and resource_id = 'cash';
  return jsonb_build_object('gems', coalesce(v_gems, 0), 'cash', coalesce(v_cash, 0));
end; $$;
grant execute on function public.economy_my_balances() to authenticated;

-- Mes ordres ouverts
create or replace function public.economy_my_orders()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid; v_rows jsonb;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  v_actor := public.economy_ensure_player();
  select coalesce(jsonb_agg(to_jsonb(o) order by o.created_at desc), '[]'::jsonb) into v_rows
    from (select id, side, gems, price, gems_remaining, status, created_at
          from public.economy_orders where actor_id = v_actor and status = 'open') o;
  return v_rows;
end; $$;
grant execute on function public.economy_my_orders() to authenticated;

-- Modifier un ordre = annuler + replacer, ATOMIQUE (même côté).
-- Si le replacement échoue (fonds insuffisants...), on lève → l'ordre d'origine
-- est restauré (rollback de l'annulation). L'ordre perd sa priorité d'ancienneté.
create or replace function public.economy_amend_order(p_order_id uuid, p_gems numeric, p_price numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid; v_order public.economy_orders; v_cancel jsonb; v_place jsonb;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if p_gems <= 0 or p_price <= 0 then return jsonb_build_object('success', false, 'error', 'invalid amounts'); end if;

  v_actor := public.economy_ensure_player();
  select * into v_order from public.economy_orders
    where id = p_order_id and actor_id = v_actor and status = 'open';
  if not found then return jsonb_build_object('success', false, 'error', 'order not found or not yours'); end if;

  -- 1) annuler (rend l'escrow restant)
  v_cancel := public.economy_cancel_order(p_order_id);
  if (v_cancel->>'success')::boolean is not true then return v_cancel; end if;

  -- 2) replacer avec les nouveaux paramètres, MÊME côté
  v_place := public.economy_place_order(v_order.side, p_gems, p_price);

  -- échec → on lève pour annuler le cancel (l'ordre d'origine est restauré)
  if (v_place->>'success')::boolean is not true then
    raise exception 'amend failed: %', coalesce(v_place->>'error', 'replacement refusé');
  end if;

  return jsonb_build_object('success', true, 'order_id', v_place->>'order_id', 'amended', true);
end; $$;
grant execute on function public.economy_amend_order(uuid, numeric, numeric) to authenticated;

