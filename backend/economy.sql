-- ============================================================================
-- Dex Heroes — L1 : Ledger + Acteurs (fondation économie)
-- À coller dans Supabase : SQL Editor → New query → Run.
-- ============================================================================
-- Principes :
-- - Ledger append-only, immuable, source de vérité
-- - Balances = projection en cache, mise à jour atomique avec ledger
-- - Conservation obligatoire (Σ deltas = 0 par ressource, sauf SYSTÈME)
-- - RLS : aucune écriture directe, tout via security definer functions
-- ============================================================================

-- 1) Ressources ---------------------------------------------------------------
create table if not exists public.economy_resources (
  id text primary key,          -- "cash", "gems"
  name text not null unique,
  created_at timestamptz not null default now()
);
alter table public.economy_resources enable row level security;
drop policy if exists "res_read_all" on public.economy_resources;
create policy "res_read_all" on public.economy_resources for select using (true);

-- Insérer les ressources de base (idempotent)
insert into public.economy_resources (id, name) values
  ('cash', 'Cash'),
  ('gems', 'Gems')
on conflict (id) do nothing;

-- 2) Acteurs ------------------------------------------------------------------
create table if not exists public.economy_actors (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('player', 'npc', 'system')),
  name text not null,
  user_id uuid references auth.users (id) on delete set null,  -- lié à un compte pour player
  policy jsonb,                 -- {"spread": 0.04, "depth": 50, ...} pour NPC
  created_at timestamptz not null default now()
);
alter table public.economy_actors enable row level security;
drop policy if exists "act_read_own_or_public" on public.economy_actors;
create policy "act_read_own_or_public" on public.economy_actors for select
  using (type = 'system' or type = 'npc' or user_id = auth.uid());

-- Créer l'acteur SYSTÈME (source/puits)
insert into public.economy_actors (id, type, name) values
  ('00000000-0000-0000-0000-000000000000'::uuid, 'system', 'SYSTEM')
on conflict (id) do nothing;

-- 3) Ledger (append-only, immuable) -------------------------------------------
create table if not exists public.economy_ledger (
  id bigserial primary key,
  tx_id uuid not null,                      -- agrupe entrées d'une même tx
  actor_id uuid not null references public.economy_actors (id),
  resource_id text not null references public.economy_resources (id),
  delta numeric not null,                   -- peut être négatif ; signé
  kind text not null,                       -- "trade", "transfer", "production", "gacha", …
  metadata jsonb,                           -- {"price": 100, "counterparty": "...", …}
  created_at timestamptz not null default now(),
  check (actor_id != '00000000-0000-0000-0000-000000000000'::uuid or kind in ('production', 'gacha'))
  -- SYSTÈME ne peut créer que via production/gacha (pas de transfer dedans)
);
alter table public.economy_ledger enable row level security;
drop policy if exists "ledger_read_own" on public.economy_ledger;
create policy "ledger_read_own" on public.economy_ledger for select
  using (actor_id = (select id from public.economy_actors where user_id = auth.uid()));

-- Lever des tentatives de modification du ledger (immuabilité)
create or replace function public.prevent_ledger_modification()
returns trigger language plpgsql as $$
begin
  raise exception 'economy_ledger is immutable';
end; $$;

drop trigger if exists prevent_ledger_update on public.economy_ledger;
create trigger prevent_ledger_update before update on public.economy_ledger
  for each row execute function prevent_ledger_modification();

drop trigger if exists prevent_ledger_delete on public.economy_ledger;
create trigger prevent_ledger_delete before delete on public.economy_ledger
  for each row execute function prevent_ledger_modification();

-- Index pour perf
create index if not exists idx_ledger_tx_id on public.economy_ledger (tx_id);
create index if not exists idx_ledger_actor on public.economy_ledger (actor_id, resource_id);
create index if not exists idx_ledger_created on public.economy_ledger (created_at desc);

-- 4) Balances (cache mutlable, projection) ------------------------------------
create table if not exists public.economy_balances (
  actor_id uuid not null,
  resource_id text not null,
  balance numeric not null default 0,
  updated_at timestamptz not null default now(),
  primary key (actor_id, resource_id),
  foreign key (actor_id) references public.economy_actors (id) on delete cascade,
  foreign key (resource_id) references public.economy_resources (id) on delete cascade
);
alter table public.economy_balances enable row level security;
drop policy if exists "bal_read_own" on public.economy_balances;
create policy "bal_read_own" on public.economy_balances for select
  using (actor_id = (select id from public.economy_actors where user_id = auth.uid()));

-- 5) Fonction atomique : poster une tx -------------------------------------------

create or replace function public.economy_post_tx(
  p_tx_id uuid,
  p_entries jsonb  -- [{"actor_id": "...", "resource_id": "cash", "delta": 100, "kind": "trade", "metadata": {...}}]
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_entry jsonb;
  v_actor_id uuid;
  v_resource_id text;
  v_delta numeric;
  v_kind text;
  v_metadata jsonb;
  v_sum_per_resource hstore := hstore(array[]::text[]);
  v_key text;
  v_current_balance numeric;
  v_new_balance numeric;
  v_system_id uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_error text;
begin
  -- Test 0 : tx_id et entries non vides
  if p_tx_id is null or p_entries is null or jsonb_array_length(p_entries) = 0 then
    return jsonb_build_object('success', false, 'error', 'empty tx or entries');
  end if;

  -- Boucle 1 : valider les entrées et accumuler les deltas par ressource
  for i in 0 .. jsonb_array_length(p_entries) - 1 loop
    v_entry := p_entries -> i;
    v_actor_id := (v_entry->>'actor_id')::uuid;
    v_resource_id := v_entry->>'resource_id';
    v_delta := (v_entry->>'delta')::numeric;
    v_kind := v_entry->>'kind';
    v_metadata := v_entry->'metadata';

    -- Validation basique
    if v_actor_id is null or v_resource_id is null or v_delta is null or v_kind is null then
      return jsonb_build_object('success', false, 'error', 'missing field in entry ' || i);
    end if;

    -- L'acteur existe
    if not exists(select 1 from public.economy_actors where id = v_actor_id) then
      return jsonb_build_object('success', false, 'error', 'actor ' || v_actor_id::text || ' not found');
    end if;

    -- La ressource existe
    if not exists(select 1 from public.economy_resources where id = v_resource_id) then
      return jsonb_build_object('success', false, 'error', 'resource ' || v_resource_id || ' not found');
    end if;

    -- Test 3 : sanité du prix (si kind = trade, metadata doit avoir price > 0)
    if v_kind = 'trade' then
      if v_metadata->>'price' is not null and (v_metadata->>'price')::numeric <= 0 then
        return jsonb_build_object('success', false, 'error', 'invalid price in trade');
      end if;
    end if;

    -- Accumuler delta par ressource
    v_key := v_resource_id;
    v_sum_per_resource := v_sum_per_resource || hstore(v_key,
      coalesce((v_sum_per_resource -> v_key)::numeric, 0) + v_delta);
  end loop;

  -- Test 1 : conservation (Σ deltas == 0 par ressource, sauf SYSTÈME crée)
  -- On accepte une tx où SYSTÈME contribue positivement (production) ou négativement (puits)
  -- mais toute autre combinaison doit sommer à zéro
  for v_key in
    select distinct resource_id from public.economy_resources
  loop
    declare
      v_sum numeric;
      v_system_contrib numeric := 0;
      v_non_system_sum numeric := 0;
    begin
      v_sum := coalesce((v_sum_per_resource -> v_key)::numeric, 0);

      -- Calculer contribution SYSTÈME et non-SYSTÈME
      for i in 0 .. jsonb_array_length(p_entries) - 1 loop
        v_entry := p_entries -> i;
        if (v_entry->>'resource_id') = v_key then
          v_delta := (v_entry->>'delta')::numeric;
          if (v_entry->>'actor_id')::uuid = v_system_id then
            v_system_contrib := v_system_contrib + v_delta;
          else
            v_non_system_sum := v_non_system_sum + v_delta;
          end if;
        end if;
      end loop;

      -- Hors SYSTÈME, la somme doit être nulle (conservation)
      if v_non_system_sum != 0 then
        return jsonb_build_object('success', false, 'error',
          'conservation failure for ' || v_key || ': non-system sum = ' || v_non_system_sum);
      end if;
    end;
  end loop;

  -- Boucle 2 : vérifier les soldes (Test 2 : bornes)
  for i in 0 .. jsonb_array_length(p_entries) - 1 loop
    v_entry := p_entries -> i;
    v_actor_id := (v_entry->>'actor_id')::uuid;
    v_resource_id := v_entry->>'resource_id';
    v_delta := (v_entry->>'delta')::numeric;

    -- Lire le solde courant (ou 0 si n'existe pas)
    select balance into v_current_balance
      from public.economy_balances
      where actor_id = v_actor_id and resource_id = v_resource_id;
    v_current_balance := coalesce(v_current_balance, 0);

    v_new_balance := v_current_balance + v_delta;

    -- Borne : solde ≥ 0, sauf SYSTÈME
    if v_new_balance < 0 and v_actor_id != v_system_id then
      return jsonb_build_object('success', false, 'error',
        'insufficient balance for actor ' || v_actor_id::text || ' resource ' || v_resource_id ||
        ': have ' || v_current_balance || ', need ' || (-v_delta));
    end if;
  end loop;

  -- Tout est bon : insérer dans ledger + mettre à jour balances
  for i in 0 .. jsonb_array_length(p_entries) - 1 loop
    v_entry := p_entries -> i;
    v_actor_id := (v_entry->>'actor_id')::uuid;
    v_resource_id := v_entry->>'resource_id';
    v_delta := (v_entry->>'delta')::numeric;
    v_kind := v_entry->>'kind';
    v_metadata := v_entry->'metadata';

    -- Insérer dans ledger (immuable)
    insert into public.economy_ledger (tx_id, actor_id, resource_id, delta, kind, metadata)
      values (p_tx_id, v_actor_id, v_resource_id, v_delta, v_kind, v_metadata);

    -- Mettre à jour balance (ou créer si n'existe pas)
    insert into public.economy_balances (actor_id, resource_id, balance, updated_at)
      values (v_actor_id, v_resource_id, v_delta, now())
      on conflict (actor_id, resource_id) do update
        set balance = public.economy_balances.balance + excluded.balance,
            updated_at = now();
  end loop;

  return jsonb_build_object('success', true, 'tx_id', p_tx_id);
end; $$;

grant execute on function public.economy_post_tx(uuid, jsonb) to authenticated;

-- 6) Fonction : lire le solde (avec RLS) ----------------------------------------

create or replace function public.economy_get_balance(p_resource_id text)
returns numeric language plpgsql security definer set search_path = public as $$
declare
  v_actor_id uuid;
  v_balance numeric;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  -- Trouver l'actor du joueur courant
  select id into v_actor_id from public.economy_actors
    where type = 'player' and user_id = auth.uid();

  if v_actor_id is null then
    -- Créer un acteur player pour ce joueur
    insert into public.economy_actors (type, name, user_id)
      values ('player', 'player_' || auth.uid()::text, auth.uid())
      returning id into v_actor_id;
    -- Initialiser les balances à 0
    insert into public.economy_balances (actor_id, resource_id, balance)
      select v_actor_id, id, 0 from public.economy_resources;
  end if;

  -- Lire le solde (cache)
  select balance into v_balance from public.economy_balances
    where actor_id = v_actor_id and resource_id = p_resource_id;

  return coalesce(v_balance, 0);
end; $$;

grant execute on function public.economy_get_balance(text) to authenticated;

-- 7) Fonction : initialiser les balances d'un joueur ---------------------

create or replace function public.economy_ensure_player()
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_actor_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select id into v_actor_id from public.economy_actors
    where type = 'player' and user_id = auth.uid();

  if v_actor_id is null then
    insert into public.economy_actors (type, name, user_id)
      values ('player', 'player_' || auth.uid()::text, auth.uid())
      returning id into v_actor_id;

    insert into public.economy_balances (actor_id, resource_id, balance)
      select v_actor_id, id, 0 from public.economy_resources
      on conflict (actor_id, resource_id) do nothing;
  end if;

  return v_actor_id;
end; $$;

grant execute on function public.economy_ensure_player() to authenticated;

-- 8) Fonction : déboguer (récupérer tous les deltas d'un actor) ----------

create or replace function public.economy_debug_ledger(p_actor_id uuid)
returns table(resource_id text, total_delta numeric) language plpgsql security definer set search_path = public as $$
begin
  return query
  select el.resource_id, sum(el.delta) as total_delta
    from public.economy_ledger el
    where el.actor_id = p_actor_id
    group by el.resource_id;
end; $$;

grant execute on function public.economy_debug_ledger(uuid) to authenticated;
