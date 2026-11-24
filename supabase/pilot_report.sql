-- Flow of Ace · pilot report queries.
-- Run in Supabase: SQL Editor → paste one query (or all) → Run. They only read data.
-- Each query is independent. "Player" = profile role 'player'. Matches = sessions without a kind; practice and surveys have kind set.

-- 1. Sign-ups: players and coaches, and how many joined a team
select
  count(*) filter (where p.role = 'player')                                   as players,
  count(*) filter (where p.role = 'coach')                                    as coaches,
  count(distinct m.user_id)                                                   as players_on_a_team,
  count(*) filter (where p.share_anonymized)                                  as share_anonymized
from public.profiles p
left join public.team_members m on m.user_id = p.id;

-- 2. Per team: players, activation and logging
with s as (
  select user_id, data, at from public.sessions
)
select t.name as team,
  count(distinct m.user_id)                                                                       as players,
  count(distinct s.user_id) filter (where s.data->>'kind' is null)                                as used_before_a_match,
  count(distinct s.user_id) filter (where s.data ? 'post')                                        as logged_a_match,
  count(*) filter (where s.data->>'kind' is null)                                                 as pre_match_sessions,
  count(*) filter (where s.data ? 'post')                                                         as matches_logged,
  round(100.0 * count(*) filter (where s.data ? 'post') / nullif(count(*) filter (where s.data->>'kind' is null), 0)) as logging_rate_pct,
  count(*) filter (where s.data->>'kind' = 'practice')                                            as practice_sessions
from public.teams t
join public.team_members m on m.team_id = t.id
left join s on s.user_id = m.user_id and s.at >= m.joined_at
group by t.name order by t.name;

-- 3. Weekly active players (any session) — is usage holding up?
select date_trunc('week', at)::date as week, count(distinct user_id) as active_players, count(*) as sessions
from public.sessions where coalesce(data->>'kind', '') <> 'survey'
group by 1 order by 1;

-- 4. Retention: of players active in their first 2 weeks, how many were still active in weeks 5–6?
with first as (select user_id, min(at) as t0 from public.sessions where coalesce(data->>'kind', '') <> 'survey' group by user_id),
act as (
  select f.user_id,
    bool_or(s.at <  f.t0 + interval '14 days')                                        as early,
    bool_or(s.at >= f.t0 + interval '28 days' and s.at < f.t0 + interval '42 days')  as weeks_5_6
  from first f join public.sessions s on s.user_id = f.user_id and coalesce(s.data->>'kind', '') <> 'survey'
  where f.t0 <= now() - interval '42 days'
  group by f.user_id
)
select count(*) filter (where early) as active_early, count(*) filter (where early and weeks_5_6) as still_active_weeks_5_6,
  round(100.0 * count(*) filter (where early and weeks_5_6) / nullif(count(*) filter (where early), 0)) as retention_pct
from act;

-- 5. Flow trend per player: average of first 3 logged matches vs last 3 (players with 6+ logged matches)
with f as (
  select user_id, at, (select avg(x::numeric) from jsonb_array_elements_text(data->'post'->'flow') x) as flow,
    row_number() over (partition by user_id order by at) as n, count(*) over (partition by user_id) as total
  from public.sessions where data ? 'post'
)
select coalesce(p.display_name, 'Player') as player, max(total) as logged,
  round(avg(flow) filter (where n <= 3), 2)              as first_3,
  round(avg(flow) filter (where n > total - 3), 2)       as last_3,
  round(avg(flow) filter (where n > total - 3) - avg(flow) filter (where n <= 3), 2) as change
from f left join public.profiles p on p.id = f.user_id
where total >= 6 group by p.display_name, f.user_id order by change desc nulls last;

-- 6. Team flow by week (all logged matches)
select date_trunc('week', at)::date as week, count(*) as matches,
  round(avg((select avg(x::numeric) from jsonb_array_elements_text(data->'post'->'flow') x)), 2) as avg_flow,
  round(avg((data->'post'->>'perf')::numeric), 2) as avg_performance
from public.sessions where data ? 'post' group by 1 order by 1;

-- 7. Which breathing method went with the best flow (all players; small numbers are noise)
select data->>'method' as method, count(*) as matches,
  round(avg((select avg(x::numeric) from jsonb_array_elements_text(data->'post'->'flow') x)), 2) as avg_flow
from public.sessions where data ? 'post' group by 1 order by avg_flow desc;

-- 8. Pilot check-in: start vs after 6 weeks (players). Scales 1–5; for "nerves" lower is better.
select data->>'phase' as phase, count(*) as answers,
  round(avg((data->'answers'->>'nerves')::numeric), 2) as nerves_hurt,
  round(avg((data->'answers'->>'zone')::numeric), 2)   as in_the_zone,
  round(avg((data->'answers'->>'serve')::numeric), 2)  as serve_confidence,
  round(avg((data->'answers'->>'useful')::numeric), 2) as app_useful,
  count(*) filter (where data->'answers'->>'routine' = 'yes')       as routine_yes,
  count(*) filter (where data->'answers'->>'routine' = 'sometimes') as routine_sometimes,
  count(*) filter (where data->'answers'->>'routine' = 'no')        as routine_no
from public.sessions where data->>'kind' = 'survey' and data->>'role' = 'player'
group by 1 order by 1;

-- 9. Which parts helped most (players, follow-up)
select part, count(*) as votes
from public.sessions, jsonb_array_elements_text(coalesce(data->'answers'->'best', '[]'::jsonb)) as part
where data->>'kind' = 'survey' and data->>'phase' = 'follow'
group by part order by votes desc;

-- 10. Coaches: dashboard usefulness and what the club would pay per season
select data->>'phase' as phase, count(*) as coaches,
  round(avg((data->'answers'->>'limit')::numeric), 2) as mental_side_limits_team,
  round(avg((data->'answers'->>'dash')::numeric), 2)  as dashboard_useful,
  count(*) filter (where data->'answers'->>'pay' = 'no')   as pay_no,
  count(*) filter (where data->'answers'->>'pay' = '100')  as pay_up_to_100,
  count(*) filter (where data->'answers'->>'pay' = '200')  as pay_up_to_200,
  count(*) filter (where data->'answers'->>'pay' = '400')  as pay_up_to_400,
  count(*) filter (where data->'answers'->>'pay' = 'more') as pay_more
from public.sessions where data->>'kind' = 'survey' and data->>'role' = 'coach'
group by 1 order by 1;

-- 11. All written answers (to read through)
select data->>'role' as role, data->>'phase' as phase, coalesce(p.display_name, 'Player') as who, a.key as question, a.value #>> '{}' as answer
from public.sessions s left join public.profiles p on p.id = s.user_id, jsonb_each(s.data->'answers') a
where s.data->>'kind' = 'survey' and a.key in ('hope', 'support', 'change', 'changed') and length(a.value #>> '{}') > 0
order by s.at;
