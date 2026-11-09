-- Run against an isolated Supabase test project as an administrative role.
-- The users and all their records are rolled back at the end.
begin;
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-000000000101', 'group-a@example.invalid'),
  ('00000000-0000-4000-8000-000000000102', 'group-b@example.invalid'),
  ('00000000-0000-4000-8000-000000000103', 'group-c@example.invalid');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000102', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000102","role":"authenticated"}', true);
insert into public.profiles(id, display_name) values ('00000000-0000-4000-8000-000000000102', 'B');
-- B's run predates joining and is still visible in the group's feed afterwards.
select public.save_run(now() - interval '8 days 1 hour', now() - interval '8 days', 3600, 100, 'couch-to-5k', 1, 'w1-r' || n, true, '[{"latitude":1,"longitude":2}]') from generate_series(1,3) n;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000101', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000101","role":"authenticated"}', true);
insert into public.profiles(id, display_name) values ('00000000-0000-4000-8000-000000000101', 'A');
select public.save_run(now(), now(), 10, 100, 'example', 1, 'w1-r1', false, '[{"latitude":3,"longitude":4}]') from generate_series(1, 4);
select set_config('test.group_id', public.create_group('Couch Escapees')::text, true);
select set_config('test.invite', public.get_group_invite(current_setting('test.group_id')::uuid)::text, true);
do $$ begin
  begin
    perform public.create_group('second');
    raise exception 'member could create a second group';
  exception when unique_violation then null;
  end;
  if (select weekly_runs from public.list_group_progress(current_setting('test.group_id')::uuid) where display_name = 'A') <> 3 then
    raise exception 'weekly contribution should be capped at three, including early finishes';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000103', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000103","role":"authenticated"}', true);
do $$ begin
  begin
    perform public.get_group_invite(current_setting('test.group_id')::uuid);
    raise exception 'non-member could read the invite';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from public.list_group_activity(current_setting('test.group_id')::uuid);
    raise exception 'non-member could read group activity';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.group_members(user_id, group_id) values (auth.uid(), current_setting('test.group_id')::uuid);
    raise exception 'direct membership write unexpectedly allowed';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000102', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000102","role":"authenticated"}', true);
select public.join_group(current_setting('test.invite')::uuid);
do $$ declare v_group uuid := current_setting('test.group_id')::uuid;
begin
  if public.get_group_invite(v_group) <> current_setting('test.invite')::uuid then raise exception 'member cannot share invite'; end if;
  if (select count(*) from public.list_group_progress(v_group)) <> 2 then raise exception 'group membership missing'; end if;
  if (select sum(weekly_runs) from public.list_group_progress(v_group)) <> 3 then raise exception 'weekly progress mismatch'; end if;
  if (select count(*) from public.list_group_activity(v_group) where member_id = auth.uid()) <> 4 then raise exception 'past runs and earned milestone not visible'; end if;
  if exists (select 1 from public.list_group_activity(v_group) a where pg_catalog.to_jsonb(a) ? 'points' or pg_catalog.to_jsonb(a) ? 'route') then
    raise exception 'activity exposes route fields';
  end if;
  if (select count(*) from public.run_routes) <> 3 then raise exception 'member can read another runner route'; end if;
  if (select count(*) from public.runs) <> 3 then raise exception 'member can directly read another runner run'; end if;
end $$;

select public.leave_group(current_setting('test.group_id')::uuid);
do $$ begin
  if (select count(*) from public.runs) <> 3 or (select count(*) from public.milestones) <> 1 then raise exception 'leaving removed personal data'; end if;
  begin
    perform * from public.list_group_activity(current_setting('test.group_id')::uuid);
    raise exception 'former member can still read group activity';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000101', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000101","role":"authenticated"}', true);
do $$ begin
  if (select count(*) from public.list_group_activity(current_setting('test.group_id')::uuid) where display_name = 'B') <> 0 then
    raise exception 'former member activity remains visible';
  end if;
end $$;
select public.leave_group(current_setting('test.group_id')::uuid);
do $$ begin
  if exists (select 1 from public.preview_group_invite(current_setting('test.invite')::uuid)) then raise exception 'empty group invite still resolves'; end if;
end $$;
reset role;
do $$ begin
  if exists (select 1 from public.running_groups where id = current_setting('test.group_id')::uuid) then raise exception 'last member leaving did not delete group'; end if;
end $$;
-- Account deletion bypasses leave_group; its cascading membership deletion must
-- also remove the empty group and its bearer invite.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000103', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000103","role":"authenticated"}', true);
select set_config('test.deleted_user_group', public.create_group('Account deletion')::text, true);
select set_config('test.deleted_user_invite', public.get_group_invite(current_setting('test.deleted_user_group')::uuid)::text, true);
reset role;
delete from auth.users where id = '00000000-0000-4000-8000-000000000103';
do $$ begin
  if exists (select 1 from public.running_groups where id = current_setting('test.deleted_user_group')::uuid)
    or exists (select 1 from public.group_invites where token = current_setting('test.deleted_user_invite')::uuid) then
    raise exception 'account deletion left an empty group or invite';
  end if;
end $$;
-- Anonymous API clients cannot invoke privileged group operations or inspect invites.
set local role anon;
do $$ begin
  if has_function_privilege(current_user, 'public.create_group(text)', 'execute')
    or has_function_privilege(current_user, 'public.get_group_invite(uuid)', 'execute')
    or has_function_privilege(current_user, 'public.preview_group_invite(uuid)', 'execute')
    or has_function_privilege(current_user, 'public.join_group(uuid)', 'execute')
    or has_function_privilege(current_user, 'public.leave_group(uuid)', 'execute')
    or has_function_privilege(current_user, 'public.list_group_progress(uuid)', 'execute')
    or has_function_privilege(current_user, 'public.list_group_activity(uuid)', 'execute')
    or has_table_privilege(current_user, 'public.group_invites', 'select') then
    raise exception 'anonymous role has group privileges';
  end if;
end $$;
reset role;
rollback;
