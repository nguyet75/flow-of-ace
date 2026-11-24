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

-- ============================================================
-- Teams, coaches and consent (added in v2). Safe to re-run.
-- ============================================================

alter table public.profiles add column if not exists role text not null default 'player';
alter table public.profiles add column if not exists mode text;
alter table public.profiles add column if not exists parent_consent boolean not null default false;
alter table public.profiles add column if not exists health_consent_at timestamptz;
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('player', 'coach'));
alter table public.profiles drop constraint if exists profiles_mode_check;
alter table public.profiles add constraint profiles_mode_check check (mode is null or mode in ('solo', 'team'));

create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60),
  code text not null unique,
  coach_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.team_members (
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  share text not null default 'summary' check (share in ('summary', 'full')),
  joined_at timestamptz not null default now(),
  primary key (team_id, user_id)
);

-- Row-level security on, with no direct policies: every read and write goes through
-- the functions below, which check who is asking.
alter table public.teams enable row level security;
alter table public.team_members enable row level security;

create or replace function public.new_team_code()
returns text language sql volatile set search_path = '' as $$
  select upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
$$;

create or replace function public.create_team(p_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare t public.teams; tries int := 0;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Give the team a name'; end if;
  loop
    begin
      insert into public.teams (name, code, coach_id) values (left(trim(p_name), 60), public.new_team_code(), auth.uid()) returning * into t;
      exit;
    exception when unique_violation then
      tries := tries + 1; if tries > 5 then raise; end if;
    end;
  end loop;
  update public.profiles set role = 'coach' where id = auth.uid();
  return jsonb_build_object('id', t.id, 'name', t.name, 'code', t.code, 'role', 'coach', 'players', 0);
end $$;

create or replace function public.join_team(p_code text, p_share text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare t public.teams;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if p_share not in ('summary', 'full') then raise exception 'Choose what to share'; end if;
  select * into t from public.teams where code = upper(trim(p_code));
  if not found then raise exception 'No team with that code. Check it with your coach.'; end if;
  if t.coach_id = auth.uid() then raise exception 'You coach this team'; end if;
  insert into public.team_members (team_id, user_id, share) values (t.id, auth.uid(), p_share)
    on conflict (team_id, user_id) do update set share = excluded.share;
  return jsonb_build_object('id', t.id, 'name', t.name, 'role', 'player', 'share', p_share);
end $$;

create or replace function public.set_team_share(p_team uuid, p_share text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_share not in ('summary', 'full') then raise exception 'Choose what to share'; end if;
  update public.team_members set share = p_share where team_id = p_team and user_id = auth.uid();
end $$;

create or replace function public.leave_team(p_team uuid)
returns void language sql security definer set search_path = '' as $$
  delete from public.team_members where team_id = p_team and user_id = auth.uid();
$$;

create or replace function public.my_teams()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select jsonb_build_object('id', t.id, 'name', t.name, 'code', t.code, 'role', 'coach',
      'players', (select count(*) from public.team_members m where m.team_id = t.id)) as x
    from public.teams t where t.coach_id = auth.uid()
    union all
    select jsonb_build_object('id', t.id, 'name', t.name, 'role', 'player', 'share', m.share)
    from public.team_members m join public.teams t on t.id = m.team_id where m.user_id = auth.uid()
  ) s;
$$;

create or replace function public.regenerate_team_code(p_team uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare c text;
begin
  update public.teams set code = public.new_team_code() where id = p_team and coach_id = auth.uid() returning code into c;
  if c is null then raise exception 'Not your team'; end if;
  return c;
end $$;

create or replace function public.remove_team_member(p_team uuid, p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.teams where id = p_team and coach_id = auth.uid()) then raise exception 'Not your team'; end if;
  delete from public.team_members where team_id = p_team and user_id = p_user;
end $$;

create or replace function public.delete_team(p_team uuid)
returns void language sql security definer set search_path = '' as $$
  delete from public.teams where id = p_team and coach_id = auth.uid();
$$;

-- Coach view. Only players who joined the team appear, only sessions since they joined,
-- and players on 'summary' sharing never expose their goals, cues, if-then plans or notes.
create or replace function public.coach_team_overview(p_team uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.teams where id = p_team and coach_id = auth.uid()) then raise exception 'Not your team'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'user_id', m.user_id, 'name', coalesce(p.display_name, 'Player'), 'position', p.position,
      'share', m.share, 'joined_at', m.joined_at,
      'sessions', coalesce((
        select jsonb_agg(case when m.share = 'full' then s.data else jsonb_build_object(
          'id', s.data->'id', 'at', s.data->'at', 'kind', s.data->'kind', 'type', s.data->'type',
          'dur', s.data->'dur', 'reps', s.data->'reps', 'made', s.data->'made',
          'pos', s.data->'pos', 'energy0', s.data->'energy0', 'energy1', s.data->'energy1', 'nerves0', s.data->'nerves0',
          'dir', s.data->'dir', 'method', s.data->'method', 'mids', s.data->'mids', 'post', s.data->'post', 'skipped', s.data->'skipped')
        end order by s.at)
        from public.sessions s where s.user_id = m.user_id and s.at >= m.joined_at), '[]'::jsonb)
    ) order by coalesce(p.display_name, 'Player')), '[]'::jsonb)
    from public.team_members m left join public.profiles p on p.id = m.user_id
    where m.team_id = p_team
  );
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'create_team(text)', 'join_team(text, text)', 'set_team_share(uuid, text)', 'leave_team(uuid)', 'my_teams()',
    'regenerate_team_code(uuid)', 'remove_team_member(uuid, uuid)', 'delete_team(uuid)', 'coach_team_overview(uuid)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  execute 'revoke all on function public.new_team_code() from public, anon, authenticated';
end $$;

-- ============================================================
-- Table privileges (v3). Newer Supabase projects don't grant table access to the API roles
-- by default. Signed-in players get exactly the access their row-level security policies allow;
-- anonymous visitors get none; team tables are reachable only through the functions above.
-- ============================================================
revoke all on public.profiles, public.sessions, public.teams, public.team_members from anon;
revoke all on public.profiles, public.sessions, public.teams, public.team_members from authenticated;
grant select, insert, update, delete on public.profiles, public.sessions to authenticated;
