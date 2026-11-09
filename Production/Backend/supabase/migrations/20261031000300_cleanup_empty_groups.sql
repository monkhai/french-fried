-- Membership can also disappear through auth.users ON DELETE CASCADE, bypassing
-- leave_group. Serialize cleanup with join_group using the same group-row lock.
create function app_private.cleanup_empty_group() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform 1 from public.running_groups where id = old.group_id for update;
  if not exists (select 1 from public.group_members where group_id = old.group_id) then
    delete from public.running_groups where id = old.group_id;
  end if;
  return old;
end;
$$;
revoke all on function app_private.cleanup_empty_group() from public, anon, authenticated;

create trigger cleanup_empty_group_after_member_delete
  after delete on public.group_members
  for each row execute function app_private.cleanup_empty_group();
