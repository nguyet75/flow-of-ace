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
alter table public.profiles add constraint profiles_role_check check (role in ('player', 'coach', 'admin'));
alter table public.profiles drop constraint if exists profiles_mode_check;
alter table public.profiles add constraint profiles_mode_check check (mode is null or mode in ('solo', 'team'));

-- ============================================================
-- Roles (v4). Everyone starts as 'player'. Only an admin can make someone a 'coach'.
-- Admins come from foa_private.admin_emails, which is filled in directly in the database
-- (SQL editor), never in this file:  insert into foa_private.admin_emails values ('you@example.com');
-- Players cannot change their own role: the trigger below resets any attempt.
-- ============================================================
create schema if not exists foa_private;
revoke all on schema foa_private from public, anon;
grant usage on schema foa_private to authenticated;
create table if not exists foa_private.admin_emails (email text primary key);
revoke all on foa_private.admin_emails from public, anon, authenticated;

create or replace function foa_private.listed_admin(p_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from foa_private.admin_emails a join auth.users u on lower(u.email) = lower(a.email) where u.id = p_id);
$$;
revoke all on function foa_private.listed_admin(uuid) from public, anon;
grant execute on function foa_private.listed_admin(uuid) to authenticated;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

create or replace function foa_private.guard_role()
returns trigger language plpgsql set search_path = '' as $$
begin
  -- Writes from the app (API roles) can never set a role. The admin functions run as the
  -- database owner, so their changes pass.
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then new.role := 'player'; else new.role := old.role; end if;
  end if;
  if foa_private.listed_admin(new.id) then new.role := 'admin'; end if;
  return new;
end $$;
drop trigger if exists profiles_guard_role on public.profiles;
create trigger profiles_guard_role before insert or update on public.profiles
  for each row execute function foa_private.guard_role();

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
  if not exists (select 1 from public.profiles where id = auth.uid() and role in ('coach', 'admin')) then raise exception 'Only coaches can create teams. Ask the club admin.'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Give the team a name'; end if;
  loop
    begin
      insert into public.teams (name, code, coach_id) values (left(trim(p_name), 60), public.new_team_code(), auth.uid()) returning * into t;
      exit;
    exception when unique_violation then
      tries := tries + 1; if tries > 5 then raise; end if;
    end;
  end loop;
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
  update public.teams set code = public.new_team_code() where id = p_team and (coach_id = auth.uid() or public.is_admin()) returning code into c;
  if c is null then raise exception 'Not your team'; end if;
  return c;
end $$;

create or replace function public.remove_team_member(p_team uuid, p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.teams where id = p_team and (coach_id = auth.uid() or public.is_admin())) then raise exception 'Not your team'; end if;
  delete from public.team_members where team_id = p_team and user_id = p_user;
end $$;

create or replace function public.delete_team(p_team uuid)
returns void language sql security definer set search_path = '' as $$
  delete from public.teams where id = p_team and (coach_id = auth.uid() or public.is_admin());
$$;

-- Coach view. Only players who joined the team appear, only sessions since they joined,
-- and players on 'summary' sharing never expose their goals, cues, if-then plans or notes to the coach.
-- The club admin sees full data (players are told this in the privacy notice).
create or replace function public.coach_team_overview(p_team uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare adm boolean := public.is_admin();
begin
  if not (adm or exists (select 1 from public.teams t join public.profiles p on p.id = t.coach_id
      where t.id = p_team and t.coach_id = auth.uid() and p.role in ('coach', 'admin'))) then raise exception 'Not your team'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'user_id', m.user_id, 'name', coalesce(p.display_name, 'Player'), 'position', p.position,
      'share', m.share, 'joined_at', m.joined_at,
      'sessions', coalesce((
        select jsonb_agg(case when m.share = 'full' or adm then s.data else jsonb_build_object(
          'id', s.data->'id', 'at', s.data->'at', 'kind', s.data->'kind', 'type', s.data->'type',
          'dur', s.data->'dur', 'reps', s.data->'reps', 'made', s.data->'made',
          'pos', s.data->'pos', 'energy0', s.data->'energy0', 'energy1', s.data->'energy1', 'nerves0', s.data->'nerves0',
          'dir', s.data->'dir', 'method', s.data->'method', 'mids', s.data->'mids', 'post', s.data->'post', 'skipped', s.data->'skipped')
        end order by s.at)
        from public.sessions s where s.user_id = m.user_id and (adm or s.at >= m.joined_at)), '[]'::jsonb)
    ) order by coalesce(p.display_name, 'Player')), '[]'::jsonb)
    from public.team_members m left join public.profiles p on p.id = m.user_id
    where m.team_id = p_team
  );
end $$;

-- ============================================================
-- Admin functions (v4). Every one checks is_admin() first.
-- ============================================================
create or replace function public.admin_users()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return (select coalesce(jsonb_agg(x order by lower(x->>'name'), x->>'email'), '[]'::jsonb) from (
    select jsonb_build_object('id', u.id, 'email', u.email, 'created_at', u.created_at, 'last_sign_in_at', u.last_sign_in_at,
      'name', coalesce(p.display_name, ''), 'role', coalesce(p.role, 'player'), 'has_profile', p.id is not null,
      'position', p.position, 'level', p.level, 'birth_year', p.birth_year, 'mode', p.mode,
      'sessions', (select count(*) from public.sessions s where s.user_id = u.id),
      'last_at', (select max(s.at) from public.sessions s where s.user_id = u.id),
      'teams', coalesce((select jsonb_agg(t.name order by t.name) from public.team_members m join public.teams t on t.id = m.team_id where m.user_id = u.id), '[]'::jsonb),
      'coaches', coalesce((select jsonb_agg(t.name order by t.name) from public.teams t where t.coach_id = u.id), '[]'::jsonb)) as x
    from auth.users u left join public.profiles p on p.id = u.id) q);
end $$;

create or replace function public.admin_user(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return jsonb_build_object(
    'profile', (select to_jsonb(p) from public.profiles p where p.id = p_user),
    'email', (select u.email from auth.users u where u.id = p_user),
    'sessions', coalesce((select jsonb_agg(s.data order by s.at) from public.sessions s where s.user_id = p_user), '[]'::jsonb));
end $$;

create or replace function public.admin_set_role(p_user uuid, p_role text)
returns void language plpgsql security definer set search_path = '' as $$
declare cur text;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if p_role not in ('player', 'coach') then raise exception 'Role must be player or coach'; end if;
  select role into cur from public.profiles where id = p_user;
  if not found then raise exception 'This person hasn’t finished setting up their profile yet'; end if;
  if cur = 'admin' then raise exception 'Admin accounts are set in the database'; end if;
  update public.profiles set role = p_role, updated_at = now() where id = p_user;
end $$;

create or replace function public.admin_teams()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'code', t.code, 'role', 'coach',
      'coach', coalesce(p.display_name, 'Coach'), 'coach_id', t.coach_id,
      'players', (select count(*) from public.team_members m where m.team_id = t.id)) order by t.name), '[]'::jsonb)
    from public.teams t left join public.profiles p on p.id = t.coach_id);
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'admin_users()', 'admin_user(uuid)', 'admin_set_role(uuid, text)', 'admin_teams()',
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
