-- Isolated test database only. All test users and runs are rolled back.
begin;
insert into auth.users(id, email) values
 ('00000000-0000-4000-8000-000000000201', 'retry-a@example.invalid'),
 ('00000000-0000-4000-8000-000000000202', 'retry-b@example.invalid');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000201', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000201","role":"authenticated"}', true);
select public.save_run_idempotent('00000000-0000-4000-8000-000000000211', '2026-01-01 10:00Z', '2026-01-01 10:01Z', 60, 100, 'test', 1, 'one', false, '[]');
select public.save_run_idempotent('00000000-0000-4000-8000-000000000211', '2026-01-01 10:00Z', '2026-01-01 10:01Z', 60, 100, 'test', 1, 'one', false, '[]');
do $$ begin
  if (select count(*) from public.runs) <> 1 or (select count(*) from public.run_routes) <> 1 then
    raise exception 'retry created duplicate data';
  end if;
  begin
    perform public.save_run_idempotent('00000000-0000-4000-8000-000000000211', '2026-01-01 10:00Z', '2026-01-01 10:01Z', 60, 101, 'test', 1, 'one', false, '[]');
    raise exception 'different payload accepted';
  exception when unique_violation then null; end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000202', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000202","role":"authenticated"}', true);
do $$ begin
  begin
    perform public.save_run_idempotent('00000000-0000-4000-8000-000000000211', '2026-01-01 10:00Z', '2026-01-01 10:01Z', 60, 100, 'test', 1, 'one', false, '[]');
    raise exception 'other user reused a run ID';
  exception when unique_violation then null; end;
  begin
    perform public.save_run_idempotent('00000000-0000-4000-8000-000000000212', '2026-01-01 10:00Z', '2026-01-01 10:01Z', 60, 100, 'test', 1, 'one', false, '{}');
    raise exception 'invalid route accepted';
  exception when check_violation then null; end;
  if (select count(*) from public.runs) <> 0 then raise exception 'invalid route left a run'; end if;
end $$;
rollback;
