-- Dedicated development project only. All fixtures roll back.
begin;
insert into auth.users(id,email) values
 ('00000000-0000-4000-8000-000000000301','progress-a@example.invalid'),
 ('00000000-0000-4000-8000-000000000302','progress-b@example.invalid');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000301',true);
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000301","role":"authenticated"}',true);
insert into public.profiles(id,display_name) values(auth.uid(),'Progress A') on conflict(id) do update set display_name=excluded.display_name;
-- Partial and misleading short completion flags never advance a session.
insert into public.runs(started_at,ended_at,active_seconds,distance_meters,program_id,program_version,session_id,session_completed)
values ('2026-01-01 10:00Z','2026-01-01 10:01Z',60,100,'couch-to-5k',1,'w1-r1',true),
       ('2026-01-01 10:00Z','2026-01-01 11:00Z',3600,100,'couch-to-5k',1,'w1-r1',false);
do $$ begin
 if exists(select 1 from public.list_my_program_progress() where completed) then raise exception 'early run advanced'; end if;
 begin update public.profiles set character_stage=9 where id=auth.uid(); raise exception 'forged stage accepted'; exception when insufficient_privilege then null; end;
 begin insert into public.milestones(program_id,program_version,kind) values('couch-to-5k',1,'program_completed'); raise exception 'forged milestone accepted'; exception when insufficient_privilege then null; end;
end $$;
-- Three repeats count once; future weeks do not bypass an incomplete week.
insert into public.runs(started_at,ended_at,active_seconds,distance_meters,program_id,program_version,session_id,session_completed)
select '2026-01-02 10:00Z','2026-01-02 11:00Z',3600,100,'couch-to-5k',1,'w1-r1',true from generate_series(1,3);
insert into public.runs(started_at,ended_at,active_seconds,distance_meters,program_id,program_version,session_id,session_completed)
select '2026-01-03 10:00Z','2026-01-03 11:00Z',3600,100,program_id,program_version,session_id,true from public.program_sessions where week=2;
do $$ begin
 if (select count(*) from public.list_my_program_progress() where completed)<>4 then raise exception 'repeat completion duplicated'; end if;
 if (select character_stage from public.profiles where id=auth.uid())<>0 or exists(select 1 from public.milestones) then raise exception 'skipped incomplete week'; end if;
end $$;
-- Completing the gap earns both contiguous weeks exactly once.
insert into public.runs(started_at,ended_at,active_seconds,distance_meters,program_id,program_version,session_id,session_completed)
select '2026-01-04 10:00Z','2026-01-04 11:00Z',3600,100,program_id,program_version,session_id,true from public.program_sessions where week=1 and run_number>1;
do $$ begin
 if (select character_stage from public.profiles where id=auth.uid())<>2 or (select current_week from public.profiles where id=auth.uid())<>3 then raise exception 'week progression wrong'; end if;
 if (select count(*) from public.milestones)<>2 then raise exception 'week milestones wrong'; end if;
end $$;
-- Complete remaining sessions, then repeat all; exactly nine weeks + graduation.
insert into public.runs(started_at,ended_at,active_seconds,distance_meters,program_id,program_version,session_id,session_completed)
select '2026-01-05 10:00Z','2026-01-05 11:00Z',3600,100,program_id,program_version,session_id,true from public.program_sessions;
do $$ begin
 if (select character_stage from public.profiles where id=auth.uid())<>9 then raise exception 'graduation missing'; end if;
 if (select count(*) from public.milestones)<>10 then raise exception 'milestones duplicated'; end if;
 -- Idempotent app retry and profile upsert preserve derived state.
 perform public.save_run_idempotent('00000000-0000-4000-8000-000000000311','2026-01-06 10:00Z','2026-01-06 11:00Z',3600,100,'couch-to-5k',1,'w9-r3',true,'[]');
 perform public.save_run_idempotent('00000000-0000-4000-8000-000000000311','2026-01-06 10:00Z','2026-01-06 11:00Z',3600,100,'couch-to-5k',1,'w9-r3',true,'[]');
 if (select count(*) from public.milestones)<>10 then raise exception 'retry duplicated milestones'; end if;
end $$;
insert into public.profiles(id,display_name) values(auth.uid(),'Renamed') on conflict(id) do update set id=excluded.id,display_name=excluded.display_name;
-- A failed route write also rolls back its progression changes.
delete from public.runs where session_id='w1-r2';
do $$ begin
 if (select character_stage from public.profiles where id=auth.uid())<>0 or exists(select 1 from public.milestones) then raise exception 'delete did not recompute'; end if;
 begin
 perform public.save_run_idempotent('00000000-0000-4000-8000-000000000312','2026-01-07 10:00Z','2026-01-07 11:00Z',3600,100,'couch-to-5k',1,'w1-r2',true,'{}');
 raise exception 'bad route accepted'; exception when check_violation then null; end;
 if (select character_stage from public.profiles where id=auth.uid())<>0 or exists(select 1 from public.milestones) then raise exception 'failed save advanced'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000302',true);
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000302","role":"authenticated"}',true);
do $$ begin
 if exists(select 1 from public.list_my_program_progress() where completed) then raise exception 'other owner progress leaked'; end if;
 if exists(select 1 from public.profiles) or exists(select 1 from public.runs) then raise exception 'other owner data leaked'; end if;
 begin perform app_private.recompute_program_progress('00000000-0000-4000-8000-000000000301'); raise exception 'private helper exposed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
