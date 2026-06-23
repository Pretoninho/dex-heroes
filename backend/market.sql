-- ============================================================================
-- Dex Heroes — Phase C : Marché de gemmes (in-game, soldes côté serveur)
-- À coller dans Supabase : SQL Editor → New query → Run.
-- ----------------------------------------------------------------------------
-- Principe : un "porte-monnaie de marché" (wallets) vit côté serveur et n'est
-- modifiable QUE par les fonctions ci-dessous (security definer = exécutées
-- avec les droits du propriétaire, donc transactions atomiques et sûres).
-- Le client ne peut jamais écrire les soldes en direct (RLS).
-- ============================================================================

-- 1) Porte-monnaie de marché -------------------------------------------------
create table if not exists public.wallets (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  gems       numeric not null default 0 check (gems >= 0),
  cash       numeric not null default 0 check (cash >= 0),
  updated_at timestamptz not null default now()
);
alter table public.wallets enable row level security;
-- Lecture : seulement SON porte-monnaie. Aucune écriture directe (tout via fonctions).
drop policy if exists "wallets_select_own" on public.wallets;
create policy "wallets_select_own" on public.wallets for select using (auth.uid() = user_id);

-- 2) Annonces (vendre des gemmes contre du cash) -----------------------------
create table if not exists public.listings (
  id          uuid primary key default gen_random_uuid(),
  seller      uuid not null references auth.users (id) on delete cascade,
  seller_name text,
  gems        numeric not null check (gems > 0),     -- gemmes mises en vente (sous séquestre)
  price       numeric not null check (price > 0),     -- prix demandé en cash
  created_at  timestamptz not null default now()
);
alter table public.listings enable row level security;
-- Lecture publique du marché ; aucune écriture directe (tout via fonctions).
drop policy if exists "listings_read_all" on public.listings;
create policy "listings_read_all" on public.listings for select using (true);

-- 3) Fonctions atomiques (le cœur de la sécurité) ----------------------------

-- Crée le porte-monnaie s'il n'existe pas.
create or replace function public.ensure_wallet()
returns public.wallets language plpgsql security definer set search_path = public as $$
declare w public.wallets;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  insert into public.wallets(user_id) values (auth.uid()) on conflict (user_id) do nothing;
  select * into w from public.wallets where user_id = auth.uid();
  return w;
end; $$;

-- Dépôt : depuis le jeu VERS le porte-monnaie de marché. (Plafonné.)
create or replace function public.deposit(d_gems numeric, d_cash numeric)
returns public.wallets language plpgsql security definer set search_path = public as $$
declare w public.wallets;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if d_gems < 0 or d_cash < 0 then raise exception 'negative amount'; end if;
  if d_gems > 1e7 or d_cash > 1e15 then raise exception 'deposit too large'; end if;
  insert into public.wallets(user_id, gems, cash) values (auth.uid(), d_gems, d_cash)
    on conflict (user_id) do update
      set gems = public.wallets.gems + excluded.gems,
          cash = public.wallets.cash + excluded.cash,
          updated_at = now()
    returning * into w;
  return w;
end; $$;

-- Retrait : du porte-monnaie VERS le jeu.
create or replace function public.withdraw(w_gems numeric, w_cash numeric)
returns public.wallets language plpgsql security definer set search_path = public as $$
declare w public.wallets;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if w_gems < 0 or w_cash < 0 then raise exception 'negative amount'; end if;
  update public.wallets set gems = gems - w_gems, cash = cash - w_cash, updated_at = now()
    where user_id = auth.uid() and gems >= w_gems and cash >= w_cash
    returning * into w;
  if not found then raise exception 'insufficient wallet balance'; end if;
  return w;
end; $$;

-- Créer une annonce : met les gemmes SOUS SÉQUESTRE (débitées du porte-monnaie).
create or replace function public.create_listing(l_gems numeric, l_price numeric)
returns public.listings language plpgsql security definer set search_path = public as $$
declare l public.listings;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if l_gems <= 0 or l_price <= 0 then raise exception 'invalid amounts'; end if;
  update public.wallets set gems = gems - l_gems, updated_at = now()
    where user_id = auth.uid() and gems >= l_gems;
  if not found then raise exception 'insufficient gems'; end if;
  insert into public.listings(seller, seller_name, gems, price)
    values (auth.uid(), (select display_name from public.scores where user_id = auth.uid()), l_gems, l_price)
    returning * into l;
  return l;
end; $$;

-- Annuler son annonce : rend les gemmes du séquestre.
create or replace function public.cancel_listing(l_id uuid)
returns public.wallets language plpgsql security definer set search_path = public as $$
declare l public.listings; w public.wallets;
begin
  delete from public.listings where id = l_id and seller = auth.uid() returning * into l;
  if not found then raise exception 'listing not found or not yours'; end if;
  update public.wallets set gems = gems + l.gems, updated_at = now()
    where user_id = auth.uid() returning * into w;
  return w;
end; $$;

-- Acheter une annonce : transfert ATOMIQUE (cash acheteur -> vendeur, gemmes -> acheteur).
create or replace function public.buy_listing(l_id uuid)
returns public.wallets language plpgsql security definer set search_path = public as $$
declare l public.listings; w public.wallets;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select * into l from public.listings where id = l_id for update;   -- verrou anti double-achat
  if not found then raise exception 'listing gone'; end if;
  if l.seller = auth.uid() then raise exception 'cannot buy own listing'; end if;
  -- débite l'acheteur (doit avoir assez de cash) et le crédite en gemmes
  update public.wallets set cash = cash - l.price, gems = gems + l.gems, updated_at = now()
    where user_id = auth.uid() and cash >= l.price returning * into w;
  if not found then raise exception 'insufficient cash'; end if;
  -- crédite le vendeur en cash
  insert into public.wallets(user_id, cash) values (l.seller, l.price)
    on conflict (user_id) do update set cash = public.wallets.cash + excluded.cash, updated_at = now();
  delete from public.listings where id = l_id;
  return w;
end; $$;

-- 4) Droits d'exécution (réservés aux utilisateurs connectés) -----------------
grant execute on function public.ensure_wallet()                   to authenticated;
grant execute on function public.deposit(numeric, numeric)         to authenticated;
grant execute on function public.withdraw(numeric, numeric)        to authenticated;
grant execute on function public.create_listing(numeric, numeric)  to authenticated;
grant execute on function public.cancel_listing(uuid)              to authenticated;
grant execute on function public.buy_listing(uuid)                 to authenticated;
