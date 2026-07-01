-- ============================================================================
-- Dex Heroes — Schéma Supabase
-- À coller dans Supabase : projet → SQL Editor → New query → Run.
-- ============================================================================

-- Phase A : sauvegarde cloud (une ligne d'état par joueur) ------------------
create table if not exists public.saves (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  state      jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.saves enable row level security;

-- Chaque joueur ne voit / n'écrit que SA propre sauvegarde.
drop policy if exists "saves_select_own" on public.saves;
create policy "saves_select_own" on public.saves
  for select using (auth.uid() = user_id);

drop policy if exists "saves_insert_own" on public.saves;
create policy "saves_insert_own" on public.saves
  for insert with check (auth.uid() = user_id);

drop policy if exists "saves_update_own" on public.saves;
create policy "saves_update_own" on public.saves
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ============================================================================
-- Phase B : classement (leaderboard).
-- ⚠️ net_worth est pour l'instant rapporté par le client (non infalsifiable).
--    À valider côté serveur (Edge Function) plus tard pour l'anti-triche.
-- ============================================================================
create table if not exists public.scores (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  net_worth    numeric not null default 0,
  ipo          int     not null default 0,   -- 📈 nb d'IPO (prestiges) → palier de plaque au classement
  parts        numeric not null default 0,   -- 📈 Parts de fondateur accumulées au total
  updated_at   timestamptz not null default now()
);
-- ⚠️ Table déjà créée ? Passer une fois dans Supabase → SQL Editor :
--   alter table public.scores add column if not exists ipo int not null default 0;
--   alter table public.scores add column if not exists parts numeric not null default 0;

alter table public.scores enable row level security;

-- Lecture publique (tout le monde voit le classement), écriture de SA ligne.
drop policy if exists "scores_read_all" on public.scores;
create policy "scores_read_all" on public.scores
  for select using (true);

drop policy if exists "scores_insert_own" on public.scores;
create policy "scores_insert_own" on public.scores
  for insert with check (auth.uid() = user_id);

drop policy if exists "scores_update_own" on public.scores;
create policy "scores_update_own" on public.scores
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
