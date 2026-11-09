-- Frozen timing contract matching ProgramCore/CouchTo5KPlan.swift v1.
create table public.program_sessions (
  program_id text not null,
  program_version integer not null,
  session_id text not null,
  week integer not null check (week between 1 and 9),
  run_number integer not null check (run_number between 1 and 3),
  duration_seconds integer not null check (duration_seconds > 0),
  primary key (program_id, program_version, session_id),
  unique (program_id, program_version, week, run_number)
);
alter table public.program_sessions enable row level security;
revoke all on public.program_sessions from public, anon, authenticated;
grant select on public.program_sessions to authenticated;
create policy program_sessions_read on public.program_sessions for select to authenticated using (true);
insert into public.program_sessions
select 'couch-to-5k', 1, 'w' || ((n-1)/3+1) || '-r' || ((n-1)%3+1),
       (n-1)/3+1, (n-1)%3+1, seconds
from unnest(array[1710,1710,1710,1740,1740,1740,1500,1500,1500,1890,1890,1890,1860,1860,1800,2040,1980,2100,2100,2100,2100,2280,2280,2280,2400,2400,2400]) with ordinality as duration(seconds, ordinal)
cross join lateral (select ordinal::integer as n) numbered;

-- Display/cosmetics remain editable; earned state cannot be supplied in upserts.
revoke insert, update on public.profiles from authenticated;
grant insert (id, display_name, equipped_cosmetic_ids), update (id, display_name, equipped_cosmetic_ids) on public.profiles to authenticated;
revoke insert, update, delete on public.milestones from authenticated;

create function public.list_my_program_progress()
returns table (session_id text, week integer, run_number integer, completed boolean)
language sql stable security invoker set search_path = ''
as $$
 select s.session_id, s.week, s.run_number, exists (
   select 1 from public.runs r where r.owner_id = (select auth.uid())
   and r.program_id = s.program_id and r.program_version = s.program_version and r.session_id = s.session_id
   and r.session_completed and r.active_seconds >= s.duration_seconds
   and extract(epoch from r.ended_at-r.started_at) + 1 >= s.duration_seconds
 ) from public.program_sessions s
 where s.program_id = 'couch-to-5k' and s.program_version = 1 and (select auth.uid()) is not null
 order by s.week, s.run_number;
$$;
revoke all on function public.list_my_program_progress() from public, anon;
grant execute on function public.list_my_program_progress() to authenticated;

-- Only invoked by triggers. Serializes competing writes for one person's runs.
create function app_private.lock_run_progress() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and new.owner_id <> old.owner_id then
    raise exception 'run_owner_is_immutable' using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    coalesce(new.owner_id, old.owner_id)::text, 921));
  return coalesce(new, old);
end;
$$;
revoke all on function app_private.lock_run_progress() from public, anon, authenticated;
create trigger lock_run_progress before insert or update or delete on public.runs
for each row execute function app_private.lock_run_progress();

create function app_private.recompute_program_progress(p_owner uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_completed_weeks integer;
  v_completed_at timestamptz[];
begin
  -- Caller is a revoked, private trigger function; RLS authorized the source write.
  -- Account deletion cascades must not recreate milestones for a deleted owner.
  if not exists (select 1 from auth.users where id = p_owner) then return; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_owner::text, 921));
  -- Earliest qualifying completion per distinct session; pauses don't count.
  with sessions as (
    select s.week, s.session_id, min(r.ended_at) as completed_at
    from public.program_sessions s left join public.runs r
      on r.owner_id = p_owner and r.program_id = s.program_id and r.program_version = s.program_version
      and r.session_id = s.session_id and r.session_completed
      and r.active_seconds >= s.duration_seconds
      and extract(epoch from r.ended_at-r.started_at) + 1 >= s.duration_seconds
    where s.program_id = 'couch-to-5k' and s.program_version = 1
    group by s.week, s.session_id
  ), weeks as (
    select week, case when count(completed_at) = 3 then max(completed_at) end as completed_at
    from sessions group by week
  ) select coalesce(min(week) filter (where completed_at is null), 10)-1,
           array_agg(completed_at order by week)
    into v_completed_weeks, v_completed_at from weeks;

  update public.profiles set current_week = least(v_completed_weeks+1,9), character_stage = v_completed_weeks
    where id = p_owner and (current_week <> least(v_completed_weeks+1,9) or character_stage <> v_completed_weeks);
  delete from public.milestones where owner_id = p_owner and program_id = 'couch-to-5k' and program_version = 1
    and ((kind = 'week_completed' and week > v_completed_weeks) or (kind = 'program_completed' and v_completed_weeks < 9));
  insert into public.milestones(owner_id, program_id, program_version, kind, week, occurred_at)
    select p_owner, 'couch-to-5k', 1, 'week_completed', n,
      (select max(t) from unnest(v_completed_at[1:n]) t)
    from generate_series(1, v_completed_weeks) n
    on conflict do nothing;
  if v_completed_weeks = 9 then
    insert into public.milestones(owner_id, program_id, program_version, kind, occurred_at)
      values (p_owner, 'couch-to-5k', 1, 'program_completed', (select max(t) from unnest(v_completed_at) t))
      on conflict do nothing;
  end if;
end;
$$;
revoke all on function app_private.recompute_program_progress(uuid) from public, anon, authenticated;

create function app_private.sync_run_progress() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.recompute_program_progress(coalesce(new.owner_id, old.owner_id));
  return null;
end;
$$;
revoke all on function app_private.sync_run_progress() from public, anon, authenticated;
create trigger sync_run_progress after insert or update or delete on public.runs
for each row execute function app_private.sync_run_progress();

create function app_private.initialize_profile_progress() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.recompute_program_progress(new.id);
  return null;
end;
$$;
revoke all on function app_private.initialize_profile_progress() from public, anon, authenticated;
create trigger initialize_profile_progress after insert on public.profiles
for each row execute function app_private.initialize_profile_progress();

-- Existing saved sessions acquire the same derived state as new sessions.
select app_private.recompute_program_progress(id) from public.profiles;
