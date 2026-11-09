-- Personal data boundary. Group sharing is introduced separately.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 80),
  created_at timestamptz not null default now()
);

create table public.runs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  active_seconds integer not null check (active_seconds >= 0),
  distance_meters double precision not null check (distance_meters >= 0 and distance_meters < 'Infinity'::double precision),
  program_id text not null check (char_length(program_id) > 0),
  program_version integer not null check (program_version > 0),
  session_id text not null check (char_length(session_id) > 0),
  session_completed boolean not null,
  created_at timestamptz not null default now(),
  constraint runs_time_order check (ended_at >= started_at),
  constraint runs_id_owner_unique unique (id, owner_id)
);

create index runs_owner_started_at_idx on public.runs (owner_id, started_at desc);

-- Coordinates stay separate: future group summaries must not expose them.
create table public.run_routes (
  run_id uuid primary key,
  owner_id uuid not null default auth.uid(),
  points jsonb not null check (jsonb_typeof(points) = 'array'),
  constraint run_routes_owned_run_fk foreign key (run_id, owner_id)
    references public.runs(id, owner_id) on delete cascade
);

alter table public.profiles enable row level security;
alter table public.runs enable row level security;
alter table public.run_routes enable row level security;

-- The app uses an authenticated user session, never a service-role key.
revoke all on public.profiles, public.runs, public.run_routes from anon, authenticated;
grant select, insert, update, delete on public.profiles, public.runs, public.run_routes to authenticated;

create policy profiles_select_own on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy profiles_insert_own on public.profiles for insert to authenticated with check (id = (select auth.uid()));
create policy profiles_update_own on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy profiles_delete_own on public.profiles for delete to authenticated using (id = (select auth.uid()));

create policy runs_select_own on public.runs for select to authenticated using (owner_id = (select auth.uid()));
create policy runs_insert_own on public.runs for insert to authenticated with check (owner_id = (select auth.uid()));
create policy runs_update_own on public.runs for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy runs_delete_own on public.runs for delete to authenticated using (owner_id = (select auth.uid()));

create policy routes_select_own on public.run_routes for select to authenticated using (owner_id = (select auth.uid()));
create policy routes_insert_own on public.run_routes for insert to authenticated with check (owner_id = (select auth.uid()));
create policy routes_update_own on public.run_routes for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy routes_delete_own on public.run_routes for delete to authenticated using (owner_id = (select auth.uid()));

-- One invoker-scoped transaction: a route failure also rolls back the run.
create function public.save_run(
  p_started_at timestamptz,
  p_ended_at timestamptz,
  p_active_seconds integer,
  p_distance_meters double precision,
  p_program_id text,
  p_program_version integer,
  p_session_id text,
  p_session_completed boolean,
  p_points jsonb
) returns uuid
language plpgsql security invoker
set search_path = ''
as $$
declare
  saved_run_id uuid;
begin
  insert into public.runs (started_at, ended_at, active_seconds, distance_meters, program_id, program_version, session_id, session_completed)
  values (p_started_at, p_ended_at, p_active_seconds, p_distance_meters, p_program_id, p_program_version, p_session_id, p_session_completed)
  returning id into saved_run_id;

  insert into public.run_routes (run_id, points) values (saved_run_id, p_points);
  return saved_run_id;
end;
$$;

revoke all on function public.save_run(timestamptz, timestamptz, integer, double precision, text, integer, text, boolean, jsonb) from public, anon;
grant execute on function public.save_run(timestamptz, timestamptz, integer, double precision, text, integer, text, boolean, jsonb) to authenticated;
