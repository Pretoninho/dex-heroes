-- ============================================================================
-- Dex Heroes — L2 : Marché sur le ledger + index de prix
-- À coller dans Supabase APRÈS economy.sql (L1).
-- ============================================================================
-- Principes :
-- - Un ordre = intention d'échange (buy/sell gemmes contre cash à un prix)
-- - Poster un ordre met les ressources SOUS SÉQUESTRE via post_tx (vers SYSTEM)
-- - Le matching croise buy/sell ; à l'exécution, post_tx libère le séquestre
--   vers les contreparties → un FAIT de trade immuable est enregistré
-- - L'index de prix = moyenne pondérée (par volume) des N derniers trades
-- ============================================================================

-- 0) Acteur ESCROW (séquestre du marché) -------------------------------------
-- On réutilise l'acteur SYSTEM comme séquestre : les ressources d'un ordre en
-- attente y sont parquées, puis redistribuées au matching. Conservation OK
-- car tout transite par des tx équilibrées (joueur <-> SYSTEM <-> joueur).

-- 1) Carnet d'ordres ----------------------------------------------------------
create table if not exists public.economy_orders (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.economy_actors (id) on delete cascade,
  side text not null check (side in ('buy', 'sell')),   -- buy = achète gemmes avec cash ; sell = vend gemmes contre cash
  gems numeric not null check (gems > 0),               -- quantité de gemmes de l'ordre
  price numeric not null check (price > 0),             -- prix unitaire en cash par gemme
  gems_remaining numeric not null check (gems_remaining >= 0),  -- restant à exécuter (fills partiels)
  status text not null default 'open' check (status in ('open', 'filled', 'cancelled')),
  created_at timestamptz not null default now()
);
alter table public.economy_orders enable row level security;
-- Lecture : carnet public (mais on n'expose que l'agrégat côté UI) + ses propres ordres
drop policy if exists "orders_read_all" on public.economy_orders;
create policy "orders_read_all" on public.economy_orders for select using (true);

create index if not exists idx_orders_match on public.economy_orders (side, status, price);
create index if not exists idx_orders_actor on public.economy_orders (actor_id);

-- 2) Faits de trade (immuables) ----------------------------------------------
create table if not exists public.economy_trades (
  id bigserial primary key,
  tx_id uuid not null,                  -- lie au ledger (la tx qui a déplacé les ressources)
  buy_order uuid,
  sell_order uuid,
  buyer_id uuid not null references public.economy_actors (id),
  seller_id uuid not null references public.economy_actors (id),
  gems numeric not null check (gems > 0),
  price numeric not null check (price > 0),    -- prix unitaire d'exécution
  cash numeric not null check (cash > 0),      -- = gems * price
  executed_at timestamptz not null default now()
);
alter table public.economy_trades enable row level security;
-- Lecture publique des faits de trade (le marché est transparent sur les prix)
drop policy if exists "trades_read_all" on public.economy_trades;
create policy "trades_read_all" on public.economy_trades for select using (true);

create index if not exists idx_trades_time on public.economy_trades (executed_at desc);

-- Immuabilité des trades
drop trigger if exists prevent_trades_update on public.economy_trades;
create trigger prevent_trades_update before update on public.economy_trades
  for each row execute function public.prevent_ledger_modification();
drop trigger if exists prevent_trades_delete on public.economy_trades;
create trigger prevent_trades_delete before delete on public.economy_trades
  for each row execute function public.prevent_ledger_modification();

-- 3) Index de prix (cache du cours) ------------------------------------------
create table if not exists public.economy_price_index (
  id text primary key default 'gems_cash',   -- une seule paire pour l'instant
  price numeric not null default 0,           -- cours courant (cash par gemme)
  volume_recent numeric not null default 0,   -- volume des N derniers trades
  trades_count integer not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.economy_price_index enable row level security;
drop policy if exists "price_read_all" on public.economy_price_index;
create policy "price_read_all" on public.economy_price_index for select using (true);

insert into public.economy_price_index (id, price) values ('gems_cash', 0)
  on conflict (id) do nothing;

-- 4) Recalculer l'index de prix (moyenne pondérée des N derniers trades) ------
create or replace function public.economy_refresh_price()
returns numeric language plpgsql security definer set search_path = public as $$
declare
  v_n integer := 20;          -- fenêtre : 20 derniers trades
  v_price numeric;
  v_volume numeric;
  v_count integer;
begin
  select
    coalesce(sum(price * gems) / nullif(sum(gems), 0), 0),
    coalesce(sum(gems), 0),
    count(*)
  into v_price, v_volume, v_count
  from (
    select price, gems from public.economy_trades
    order by executed_at desc limit v_n
  ) recent;

  update public.economy_price_index
    set price = v_price, volume_recent = v_volume, trades_count = v_count, updated_at = now()
    where id = 'gems_cash';

  return v_price;
end; $$;

grant execute on function public.economy_refresh_price() to authenticated;

-- 5) Lire le cours courant ----------------------------------------------------
create or replace function public.economy_get_price()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_row public.economy_price_index;
begin
  select * into v_row from public.economy_price_index where id = 'gems_cash';
  return jsonb_build_object(
    'price', v_row.price,
    'volume_recent', v_row.volume_recent,
    'trades_count', v_row.trades_count,
    'updated_at', v_row.updated_at
  );
end; $$;

grant execute on function public.economy_get_price() to authenticated;

-- 6) Poster un ordre (escrow via ledger) -------------------------------------
-- buy  : on parque le CASH (gems*price) du joueur vers SYSTEM (séquestre)
-- sell : on parque les GEMS du joueur vers SYSTEM (séquestre)
create or replace function public.economy_place_order(
  p_side text, p_gems numeric, p_price numeric
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_actor_id uuid;
  v_system_id uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_tx_id uuid := gen_random_uuid();
  v_cash numeric;
  v_result jsonb;
  v_order public.economy_orders;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if p_side not in ('buy', 'sell') then raise exception 'invalid side'; end if;
  if p_gems <= 0 or p_price <= 0 then raise exception 'invalid amounts'; end if;

  v_actor_id := public.economy_ensure_player();
  v_cash := p_gems * p_price;

  -- Escrow : déplacer les ressources du joueur vers SYSTEM (séquestre)
  if p_side = 'buy' then
    v_result := public.economy_post_tx(v_tx_id, jsonb_build_array(
      jsonb_build_object('actor_id', v_actor_id,  'resource_id', 'cash', 'delta', -v_cash, 'kind', 'escrow'),
      jsonb_build_object('actor_id', v_system_id, 'resource_id', 'cash', 'delta',  v_cash, 'kind', 'escrow')
    ));
  else
    v_result := public.economy_post_tx(v_tx_id, jsonb_build_array(
      jsonb_build_object('actor_id', v_actor_id,  'resource_id', 'gems', 'delta', -p_gems, 'kind', 'escrow'),
      jsonb_build_object('actor_id', v_system_id, 'resource_id', 'gems', 'delta',  p_gems, 'kind', 'escrow')
    ));
  end if;

  if (v_result->>'success')::boolean is not true then
    return jsonb_build_object('success', false, 'error', v_result->>'error');
  end if;

  -- Inscrire l'ordre au carnet
  insert into public.economy_orders (actor_id, side, gems, price, gems_remaining)
    values (v_actor_id, p_side, p_gems, p_price, p_gems)
    returning * into v_order;

  -- Tenter le matching immédiatement
  perform public.economy_match_orders();

  return jsonb_build_object('success', true, 'order_id', v_order.id);
end; $$;

grant execute on function public.economy_place_order(text, numeric, numeric) to authenticated;

-- 7) Moteur de matching -------------------------------------------------------
-- Croise les ordres buy (prix décroissant) avec les ordres sell (prix croissant).
-- Un match a lieu quand buy.price >= sell.price. Prix d'exécution = prix du sell
-- (l'ordre le plus ancien fait le prix → "maker"). Fills partiels gérés.
create or replace function public.economy_match_orders()
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_buy public.economy_orders;
  v_sell public.economy_orders;
  v_system_id uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_qty numeric;
  v_exec_price numeric;
  v_cash numeric;
  v_tx_id uuid;
  v_matches integer := 0;
begin
  loop
    -- Meilleur acheteur (prix le plus haut, le plus ancien)
    select * into v_buy from public.economy_orders
      where side = 'buy' and status = 'open' and gems_remaining > 0
      order by price desc, created_at asc limit 1;

    -- Meilleur vendeur (prix le plus bas, le plus ancien)
    select * into v_sell from public.economy_orders
      where side = 'sell' and status = 'open' and gems_remaining > 0
      order by price asc, created_at asc limit 1;

    -- Plus de contrepartie ou pas de croisement → stop
    exit when v_buy.id is null or v_sell.id is null;
    exit when v_buy.price < v_sell.price;
    -- Un acteur ne matche pas avec lui-même : on saute (ferme le plus récent)
    if v_buy.actor_id = v_sell.actor_id then
      exit;  -- simplification v1 : on s'arrête (évite la boucle infinie)
    end if;

    -- Quantité échangée = min des restants
    v_qty := least(v_buy.gems_remaining, v_sell.gems_remaining);
    v_exec_price := v_sell.price;          -- le maker (sell) fait le prix
    v_cash := v_qty * v_exec_price;
    v_tx_id := gen_random_uuid();

    -- Régler depuis le séquestre (SYSTEM) :
    --  - le vendeur reçoit le cash de l'acheteur (qui est déjà chez SYSTEM)
    --  - l'acheteur reçoit les gems du vendeur (déjà chez SYSTEM)
    --  - si l'acheteur avait séquestré à un prix > exec, on lui rend la différence
    perform public.economy_post_tx(v_tx_id, jsonb_build_array(
      -- gems : SYSTEM -> acheteur
      jsonb_build_object('actor_id', v_system_id,    'resource_id', 'gems', 'delta', -v_qty, 'kind', 'trade', 'metadata', jsonb_build_object('price', v_exec_price)),
      jsonb_build_object('actor_id', v_buy.actor_id, 'resource_id', 'gems', 'delta',  v_qty, 'kind', 'trade', 'metadata', jsonb_build_object('price', v_exec_price)),
      -- cash : SYSTEM -> vendeur
      jsonb_build_object('actor_id', v_system_id,     'resource_id', 'cash', 'delta', -v_cash, 'kind', 'trade', 'metadata', jsonb_build_object('price', v_exec_price)),
      jsonb_build_object('actor_id', v_sell.actor_id, 'resource_id', 'cash', 'delta',  v_cash, 'kind', 'trade', 'metadata', jsonb_build_object('price', v_exec_price))
    ));

    -- Rendre à l'acheteur la sur-réservation (il avait séquestré buy.price, exec <= buy.price)
    if v_buy.price > v_exec_price then
      declare v_refund numeric := v_qty * (v_buy.price - v_exec_price);
      begin
        perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
          jsonb_build_object('actor_id', v_system_id,    'resource_id', 'cash', 'delta', -v_refund, 'kind', 'refund'),
          jsonb_build_object('actor_id', v_buy.actor_id, 'resource_id', 'cash', 'delta',  v_refund, 'kind', 'refund')
        ));
      end;
    end if;

    -- Enregistrer le FAIT de trade
    insert into public.economy_trades (tx_id, buy_order, sell_order, buyer_id, seller_id, gems, price, cash)
      values (v_tx_id, v_buy.id, v_sell.id, v_buy.actor_id, v_sell.actor_id, v_qty, v_exec_price, v_cash);

    -- Décrémenter les restants + clôturer si plein
    update public.economy_orders set gems_remaining = gems_remaining - v_qty,
      status = case when gems_remaining - v_qty <= 0 then 'filled' else 'open' end
      where id = v_buy.id;
    update public.economy_orders set gems_remaining = gems_remaining - v_qty,
      status = case when gems_remaining - v_qty <= 0 then 'filled' else 'open' end
      where id = v_sell.id;

    v_matches := v_matches + 1;
    exit when v_matches > 100;  -- garde-fou anti-boucle
  end loop;

  -- Rafraîchir le cours après les exécutions
  if v_matches > 0 then perform public.economy_refresh_price(); end if;

  return v_matches;
end; $$;

grant execute on function public.economy_match_orders() to authenticated;

-- 8) Annuler un ordre (rendre le séquestre) ----------------------------------
create or replace function public.economy_cancel_order(p_order_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_actor_id uuid;
  v_system_id uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_order public.economy_orders;
  v_refund numeric;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  v_actor_id := public.economy_ensure_player();

  select * into v_order from public.economy_orders
    where id = p_order_id and actor_id = v_actor_id and status = 'open' for update;
  if not found then return jsonb_build_object('success', false, 'error', 'order not found or not yours'); end if;

  -- Rendre le restant séquestré
  if v_order.side = 'buy' then
    v_refund := v_order.gems_remaining * v_order.price;   -- cash
    perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id', v_system_id, 'resource_id', 'cash', 'delta', -v_refund, 'kind', 'unescrow'),
      jsonb_build_object('actor_id', v_actor_id,  'resource_id', 'cash', 'delta',  v_refund, 'kind', 'unescrow')
    ));
  else
    perform public.economy_post_tx(gen_random_uuid(), jsonb_build_array(
      jsonb_build_object('actor_id', v_system_id, 'resource_id', 'gems', 'delta', -v_order.gems_remaining, 'kind', 'unescrow'),
      jsonb_build_object('actor_id', v_actor_id,  'resource_id', 'gems', 'delta',  v_order.gems_remaining, 'kind', 'unescrow')
    ));
  end if;

  update public.economy_orders set status = 'cancelled' where id = p_order_id;
  return jsonb_build_object('success', true);
end; $$;

grant execute on function public.economy_cancel_order(uuid) to authenticated;

-- 9) Carnet agrégé (pour l'UI) -----------------------------------------------
create or replace function public.economy_orderbook()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_bids jsonb; v_asks jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) into v_bids from (
    select price, sum(gems_remaining) as gems from public.economy_orders
    where side = 'buy' and status = 'open' group by price order by price desc limit 10
  ) r;
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) into v_asks from (
    select price, sum(gems_remaining) as gems from public.economy_orders
    where side = 'sell' and status = 'open' group by price order by price asc limit 10
  ) r;
  return jsonb_build_object('bids', v_bids, 'asks', v_asks);
end; $$;

grant execute on function public.economy_orderbook() to authenticated;
