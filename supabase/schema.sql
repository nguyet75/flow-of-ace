-- Flow of Ace: accounts, player profiles and session history.
-- Run this once in Supabase: Dashboard → SQL Editor → New query → paste → Run.
-- Every table uses row-level security, so each player can only read and change their own rows.

-- Player profile (one row per account)
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text check (char_length(display_name) <= 60),
  position text check (position in ('setter', 'hitter', 'middle', 'libero')),
  level text check (level in ('school', 'club', 'college', 'pro', 'beach')),
  birth_year int check (birth_year between 1900 and 2100),
  consent_at timestamptz,
  share_anonymized boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles: read own" on public.profiles;
drop policy if exists "profiles: insert own" on public.profiles;
drop policy if exists "profiles: update own" on public.profiles;
drop policy if exists "profiles: delete own" on public.profiles;
create policy "profiles: read own" on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy "profiles: insert own" on public.profiles for insert to authenticated with check ((select auth.uid()) = id);
create policy "profiles: update own" on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy "profiles: delete own" on public.profiles for delete to authenticated using ((select auth.uid()) = id);

-- One row per pre-match session (check-in, tuning, mindset, mid-match checks, post-match flow ratings).
-- The app keeps the full session as JSON so new fields don't need a migration.
create table if not exists public.sessions (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null check (char_length(id) <= 40),
  at timestamptz not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create index if not exists sessions_user_at on public.sessions (user_id, at);

alter table public.sessions enable row level security;

drop policy if exists "sessions: read own" on public.sessions;
drop policy if exists "sessions: insert own" on public.sessions;
drop policy if exists "sessions: update own" on public.sessions;
drop policy if exists "sessions: delete own" on public.sessions;
create policy "sessions: read own" on public.sessions for select to authenticated using ((select auth.uid()) = user_id);
create policy "sessions: insert own" on public.sessions for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "sessions: update own" on public.sessions for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "sessions: delete own" on public.sessions for delete to authenticated using ((select auth.uid()) = user_id);

-- Lets a signed-in player delete their own account. Profile and sessions go with it (on delete cascade).
create or replace function public.delete_my_account()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from auth.users where id = (select auth.uid());
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
