-- Group access uses explicitly scoped functions; route coordinates remain owner-only.

alter table public.profiles
  add column current_week integer not null default 1 check (current_week between 1 and 9),
  add column character_stage integer not null default 0 check (character_stage between 0 and 9),
  add column equipped_cosmetic_ids text[] not null default '{}';

create table public.running_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 80),
  created_at timestamptz not null default now()
);
create table public.group_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  group_id uuid not null references public.running_groups(id) on delete cascade,
  joined_at timestamptz not null default now()
);
create index group_members_group_idx on public.group_members(group_id);
-- The random token is a bearer capability; it is never exposed by a group SELECT.
create table public.group_invites (
  group_id uuid primary key references public.running_groups(id) on delete cascade,
  token uuid not null unique default gen_random_uuid()
);

-- Personal milestones exist independently of group membership and survive leaving.
create table public.milestones (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  program_id text not null check (char_length(program_id) > 0),
  program_version integer not null check (program_version > 0),
  kind text not null check (kind in ('week_completed', 'program_completed')),
  week integer,
  occurred_at timestamptz not null default now(),
  check ((kind = 'week_completed' and week is not null and week between 1 and 9) or (kind = 'program_completed' and week is null))
);
create unique index milestones_week_once on public.milestones(owner_id, program_id, program_version, week) where kind = 'week_completed';
create unique index milestones_program_once on public.milestones(owner_id, program_id, program_version) where kind = 'program_completed';

alter table public.running_groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_invites enable row level security;
alter table public.milestones enable row level security;
revoke all on public.running_groups, public.group_members, public.group_invites, public.milestones from public, anon, authenticated;
grant select on public.running_groups, public.group_members to authenticated;
grant select, insert, update, delete on public.milestones to authenticated;

-- Used by SELECT policies only. This exposes membership of the caller, not arbitrary users.
create schema if not exists app_private;
revoke all on schema app_private from public, anon;
grant usage on schema app_private to authenticated;
create function app_private.is_group_member(p_group_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.group_members m where m.group_id = p_group_id and m.user_id = auth.uid())
$$;
revoke all on function app_private.is_group_member(uuid) from public, anon;
grant execute on function app_private.is_group_member(uuid) to authenticated;

create policy groups_select_member on public.running_groups for select to authenticated
  using (app_private.is_group_member(id));
create policy members_select_group on public.group_members for select to authenticated
  using (app_private.is_group_member(group_id));
create policy milestones_select_own on public.milestones for select to authenticated using (owner_id = (select auth.uid()));
create policy milestones_insert_own on public.milestones for insert to authenticated with check (owner_id = (select auth.uid()));
create policy milestones_update_own on public.milestones for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy milestones_delete_own on public.milestones for delete to authenticated using (owner_id = (select auth.uid()));

-- Definer operations enforce membership, are transactional, and never accept a user ID.
create function public.create_group(p_name text) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_group uuid;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  if p_name is null or pg_catalog.char_length(pg_catalog.btrim(p_name)) not between 1 and 80 then
    raise exception 'invalid_group_name' using errcode = '22023';
  end if;
  if exists (select 1 from public.group_members where user_id = v_user) then
    raise exception 'already_in_group' using errcode = '23505';
  end if;
  insert into public.running_groups(name) values (pg_catalog.btrim(p_name)) returning id into v_group;
  insert into public.group_members(user_id, group_id) values (v_user, v_group);
  insert into public.group_invites(group_id) values (v_group);
  return v_group;
end;
$$;

create function public.get_group_invite(p_group_id uuid) returns uuid
language plpgsql stable security definer set search_path = ''
as $$
declare v_token uuid;
begin
  if not app_private.is_group_member(p_group_id) then raise exception 'not_a_group_member' using errcode = '42501'; end if;
  select token into v_token from public.group_invites where group_id = p_group_id;
  return v_token;
end;
$$;

create function public.preview_group_invite(p_token uuid) returns table(group_id uuid, group_name text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  return query select g.id, g.name from public.running_groups g join public.group_invites i on i.group_id = g.id where i.token = p_token;
end;
$$;

create function public.join_group(p_token uuid) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_group uuid; v_existing uuid;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  -- Lock the group row to serialize joining with deletion after the last leave.
  select g.id into v_group from public.running_groups g
    join public.group_invites i on i.group_id = g.id where i.token = p_token for update of g;
  if v_group is null then raise exception 'invalid_invite' using errcode = '22023'; end if;
  select group_id into v_existing from public.group_members where user_id = v_user;
  if v_existing = v_group then return v_group; end if;
  if v_existing is not null then raise exception 'already_in_group' using errcode = '23505'; end if;
  insert into public.group_members(user_id, group_id) values (v_user, v_group);
  return v_group;
end;
$$;

create function public.leave_group(p_group_id uuid) returns void
language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  perform 1 from public.running_groups where id = p_group_id for update;
  if not exists (select 1 from public.group_members where group_id = p_group_id and user_id = v_user) then
    raise exception 'not_a_group_member' using errcode = '42501';
  end if;
  delete from public.group_members where group_id = p_group_id and user_id = v_user;
  if not exists (select 1 from public.group_members where group_id = p_group_id) then
    delete from public.running_groups where id = p_group_id;
  end if;
end;
$$;

-- Weekly counts are per current group member, capped at three saved runs; reset Monday UTC.
create function public.list_group_progress(p_group_id uuid)
returns table(member_id uuid, display_name text, current_week integer, character_stage integer, equipped_cosmetic_ids text[], weekly_runs integer)
language plpgsql stable security definer set search_path = ''
as $$
declare v_week_start timestamptz := pg_catalog.date_trunc('week', pg_catalog.now() at time zone 'UTC') at time zone 'UTC';
begin
  if not app_private.is_group_member(p_group_id) then raise exception 'not_a_group_member' using errcode = '42501'; end if;
  return query
    select m.user_id, coalesce(p.display_name, 'Potato'), coalesce(p.current_week, 1), coalesce(p.character_stage, 0), coalesce(p.equipped_cosmetic_ids, '{}'::text[]),
      least(3, (select pg_catalog.count(*)::integer from public.runs r where r.owner_id = m.user_id and r.ended_at >= v_week_start and r.ended_at < v_week_start + interval '7 days'))
    from public.group_members m left join public.profiles p on p.id = m.user_id
    where m.group_id = p_group_id order by m.joined_at, m.user_id;
end;
$$;

-- Explicit columns only: no route table or coordinates can appear in this output.
create function public.list_group_activity(p_group_id uuid)
returns table(activity_id uuid, activity_kind text, occurred_at timestamptz, member_id uuid, display_name text,
  distance_meters double precision, active_seconds integer, session_completed boolean, milestone_week integer,
  program_id text, program_version integer, session_id text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not app_private.is_group_member(p_group_id) then raise exception 'not_a_group_member' using errcode = '42501'; end if;
  return query
    select a.activity_id, a.activity_kind, a.occurred_at, a.member_id, a.display_name,
           a.distance_meters, a.active_seconds, a.session_completed, a.milestone_week,
           a.program_id, a.program_version, a.session_id
    from (
      select r.id as activity_id, 'run'::text as activity_kind, r.ended_at as occurred_at, r.owner_id as member_id,
        coalesce(p.display_name, 'Potato') as display_name, r.distance_meters, r.active_seconds, r.session_completed, null::integer as milestone_week,
        r.program_id, r.program_version, r.session_id
      from public.runs r join public.group_members m on m.user_id = r.owner_id
        left join public.profiles p on p.id = r.owner_id where m.group_id = p_group_id
      union all
      select x.id, x.kind, x.occurred_at, x.owner_id, coalesce(p.display_name, 'Potato'),
        null::double precision, null::integer, null::boolean, x.week, x.program_id, x.program_version, null::text
      from public.milestones x join public.group_members m on m.user_id = x.owner_id
        left join public.profiles p on p.id = x.owner_id where m.group_id = p_group_id
    ) a order by a.occurred_at desc, a.activity_id;
end;
$$;

revoke all on function public.create_group(text), public.get_group_invite(uuid), public.preview_group_invite(uuid), public.join_group(uuid), public.leave_group(uuid), public.list_group_progress(uuid), public.list_group_activity(uuid) from public, anon;
grant execute on function public.create_group(text), public.get_group_invite(uuid), public.preview_group_invite(uuid), public.join_group(uuid), public.leave_group(uuid), public.list_group_progress(uuid), public.list_group_activity(uuid) to authenticated;
