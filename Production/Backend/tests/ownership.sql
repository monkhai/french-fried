-- Run as the database administrator against an isolated Supabase test project.
-- All rows are rolled back, including the temporary auth.users records.
begin;
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-000000000001', 'runner-a@example.invalid'),
  ('00000000-0000-4000-8000-000000000002', 'runner-b@example.invalid');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
insert into public.profiles (id, display_name) values ('00000000-0000-4000-8000-000000000001', 'Runner A');
select public.save_run(now(), now(), 10, 20, 'example', 1, 'w1-r1', false, '[{"latitude":32,"longitude":34}]');

do $$ begin
  if (select count(*) from public.runs) <> 1 or (select count(*) from public.run_routes) <> 1 then
    raise exception 'owner cannot read their own run and route';
  end if;
  begin
    perform public.save_run(now(), now(), 10, 20, 'example', 1, 'w1-r1', false, '{"not":"an array"}');
    raise exception 'invalid route was accepted';
  exception when check_violation then
    null;
  end;
  if (select count(*) from public.runs) <> 1 then
    raise exception 'failed route insertion left a partial run';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
do $$ begin
  if (select count(*) from public.runs) <> 0 or (select count(*) from public.run_routes) <> 0 then
    raise exception 'another user can read a private run or route';
  end if;
  begin
    insert into public.runs (owner_id, started_at, ended_at, active_seconds, distance_meters, program_id, program_version, session_id, session_completed)
    values ('00000000-0000-4000-8000-000000000001', now(), now(), 1, 1, 'example', 1, 'w1-r1', false);
    raise exception 'another user could create a run for the owner';
  exception when insufficient_privilege then
    null; -- The row policy rejected the forged owner ID.
  end;
end $$;
rollback;
