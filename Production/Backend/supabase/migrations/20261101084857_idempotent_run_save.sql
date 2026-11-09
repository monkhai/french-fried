-- The caller supplies a stable UUID for one immutable submission. A retry after
-- a lost response either returns the same ID or rejects a conflicting payload.
create function public.save_run_idempotent(
  p_run_id uuid, p_started_at timestamptz, p_ended_at timestamptz,
  p_active_seconds integer, p_distance_meters double precision,
  p_program_id text, p_program_version integer, p_session_id text,
  p_session_completed boolean, p_points jsonb
) returns uuid
language plpgsql security invoker set search_path = ''
as $$
declare v_inserted boolean;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  if p_run_id is null then raise exception 'run_id_required' using errcode = '22023'; end if;
  insert into public.runs (id, started_at, ended_at, active_seconds, distance_meters, program_id, program_version, session_id, session_completed)
  values (p_run_id, p_started_at, p_ended_at, p_active_seconds, p_distance_meters, p_program_id, p_program_version, p_session_id, p_session_completed)
  on conflict (id) do nothing;
  v_inserted := found;
  if v_inserted then
    insert into public.run_routes (run_id, points) values (p_run_id, p_points);
  elsif not exists (
    select 1 from public.runs r join public.run_routes route on route.run_id = r.id and route.owner_id = r.owner_id
    where r.id = p_run_id and r.owner_id = auth.uid()
      and r.started_at = p_started_at and r.ended_at = p_ended_at
      and r.active_seconds = p_active_seconds and r.distance_meters = p_distance_meters
      and r.program_id = p_program_id and r.program_version = p_program_version
      and r.session_id = p_session_id and r.session_completed = p_session_completed
      and route.points = p_points
  ) then
    raise exception 'run_id_conflict' using errcode = '23505';
  end if;
  return p_run_id;
end;
$$;
revoke all on function public.save_run_idempotent(uuid, timestamptz, timestamptz, integer, double precision, text, integer, text, boolean, jsonb) from public, anon;
grant execute on function public.save_run_idempotent(uuid, timestamptz, timestamptz, integer, double precision, text, integer, text, boolean, jsonb) to authenticated;
