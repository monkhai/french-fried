-- Disposable fixtures only. Everything, including deletion, is rolled back.
begin;
insert into auth.users(id, email) values ('00000000-0000-4000-8000-000000000901', 'deletion-test@example.invalid');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000901', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000901","role":"authenticated"}', true);
insert into public.profiles(id, display_name) values ('00000000-0000-4000-8000-000000000901', 'Deletion fixture');
select public.save_run(now() - interval '1 minute', now(), 60, 100, 'free-run', 1, 'free-run', false, '[{"latitude":1,"longitude":2}]');
select set_config('test.deletion_group', public.create_group('Deletion fixture')::text, true);
reset role;
delete from auth.users where id = '00000000-0000-4000-8000-000000000901';
do $$ begin
  if exists(select 1 from public.profiles where id = '00000000-0000-4000-8000-000000000901')
    or exists(select 1 from public.runs where owner_id = '00000000-0000-4000-8000-000000000901')
    or exists(select 1 from public.run_routes where owner_id = '00000000-0000-4000-8000-000000000901')
    or exists(select 1 from public.milestones where owner_id = '00000000-0000-4000-8000-000000000901')
    or exists(select 1 from public.group_members where user_id = '00000000-0000-4000-8000-000000000901')
    or exists(select 1 from public.running_groups where id = current_setting('test.deletion_group')::uuid)
    or exists(select 1 from public.group_invites where group_id = current_setting('test.deletion_group')::uuid)
  then raise exception 'account data survived deletion'; end if;
end $$;
-- A still-unexpired JWT cannot recreate data for a deleted account.
set local role authenticated;
do $$ begin
  begin
    insert into public.profiles(id, display_name) values ('00000000-0000-4000-8000-000000000901', 'Stale JWT');
    raise exception 'deleted account could recreate profile';
  exception when foreign_key_violation then null; end;
  begin
    perform public.create_group('Stale JWT');
    raise exception 'deleted account could create a group';
  exception when foreign_key_violation then null; end;
end $$;
reset role;
rollback;
