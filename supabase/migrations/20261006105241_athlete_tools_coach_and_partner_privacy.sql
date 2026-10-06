-- Consent is changed only by the athlete; acceptance only by the invited coach.
create table public.athlete_coach_connections (
 id uuid primary key default gen_random_uuid(),
 athlete_id uuid not null references auth.users(id) on delete cascade,
 coach_id uuid not null references auth.users(id) on delete cascade,
 state text not null default 'pending' check (state in ('pending','active','revoked')),
 share_workouts boolean not null default false,
 share_plan boolean not null default false,
 share_readiness boolean not null default false,
 created_at timestamptz not null default now(),
 unique(athlete_id,coach_id), check (athlete_id <> coach_id)
);
create index athlete_coach_connections_coach_idx on public.athlete_coach_connections(coach_id);
create table public.athlete_coach_snapshots (
 connection_id uuid primary key references public.athlete_coach_connections(id) on delete cascade,
 plan_text text check (length(plan_text) <= 25000),
 workouts jsonb check (jsonb_typeof(workouts) = 'array' and jsonb_array_length(workouts) <= 20),
 readiness_score integer check (readiness_score between 0 and 100),
 updated_at timestamptz not null default now()
);
create table public.athlete_coach_feedback (
 id uuid primary key default gen_random_uuid(),
 connection_id uuid not null references public.athlete_coach_connections(id) on delete cascade,
 author_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check (kind in ('comment','proposal')),
 body text not null check (length(btrim(body)) between 1 and 4000),
 created_at timestamptz not null default now()
);
create index athlete_coach_feedback_connection_idx on public.athlete_coach_feedback(connection_id,created_at);
create index athlete_coach_feedback_author_idx on public.athlete_coach_feedback(author_id);
alter table public.athlete_coach_connections enable row level security;
alter table public.athlete_coach_snapshots enable row level security;
alter table public.athlete_coach_feedback enable row level security;
revoke all on public.athlete_coach_connections, public.athlete_coach_snapshots, public.athlete_coach_feedback from anon, authenticated;
grant select on public.athlete_coach_connections, public.athlete_coach_snapshots, public.athlete_coach_feedback to authenticated;
grant insert on public.athlete_coach_feedback to authenticated;
create policy coach_connections_read on public.athlete_coach_connections for select to authenticated using (
 (athlete_id = (select auth.uid()) or coach_id = (select auth.uid()))
 and not private.is_blocked(case when athlete_id = (select auth.uid()) then coach_id else athlete_id end)
);
create policy coach_snapshots_read on public.athlete_coach_snapshots for select to authenticated using (
 exists(select 1 from public.athlete_coach_connections c where c.id = connection_id and c.state = 'active')
);
create policy coach_feedback_read on public.athlete_coach_feedback for select to authenticated using (
 exists(select 1 from public.athlete_coach_connections c where c.id = connection_id and c.state = 'active')
);
create policy coach_feedback_insert on public.athlete_coach_feedback for insert to authenticated with check (
 author_id = (select auth.uid()) and exists (
 select 1 from public.athlete_coach_connections c where c.id = connection_id and c.state = 'active'
 and (kind = 'comment' or c.coach_id = (select auth.uid())))
);

create function private.manage_athlete_coach(p_action text, p_connection uuid, p_coach uuid,
 p_workouts boolean, p_plan boolean, p_readiness boolean) returns uuid
language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); c public.athlete_coach_connections; result uuid;
begin
 if actor is null then raise exception 'Sign in required' using errcode='42501'; end if;
 if p_action = 'request' then
  if p_coach is null or actor = p_coach or private.is_blocked(p_coach)
    or not exists(select 1 from public.profile_follows where follower_id = actor and following_id = p_coach)
  then raise exception 'Choose an unblocked athlete you follow' using errcode='42501'; end if;
  if exists(select 1 from public.athlete_coach_connections where athlete_id=actor and coach_id=p_coach and state <> 'revoked')
  then raise exception 'Already connected. Edit the existing connection instead'; end if;
  if (select count(*) from public.athlete_coach_connections where athlete_id=actor and state <> 'revoked') >= 20
  then raise exception 'Too many coach connections'; end if;
  insert into public.athlete_coach_connections(athlete_id,coach_id,share_workouts,share_plan,share_readiness)
   values(actor,p_coach,coalesce(p_workouts,false),coalesce(p_plan,false),coalesce(p_readiness,false))
   on conflict(athlete_id,coach_id) do update set state='pending',share_workouts=excluded.share_workouts,
   share_plan=excluded.share_plan,share_readiness=excluded.share_readiness
   returning id into result;
  delete from public.athlete_coach_snapshots where connection_id=result;
  delete from public.athlete_coach_feedback where connection_id=result;
  return result;
 end if;
 select * into c from public.athlete_coach_connections where id=p_connection for update;
 if not found or actor not in (c.athlete_id,c.coach_id) or private.is_blocked(case when actor=c.athlete_id then c.coach_id else c.athlete_id end)
 then raise exception 'Connection unavailable' using errcode='42501'; end if;
 if p_action = 'accept' and actor=c.coach_id and c.state='pending' then
  update public.athlete_coach_connections set state='active' where id=c.id;
 elsif p_action = 'scopes' and actor=c.athlete_id and c.state <> 'revoked' then
  update public.athlete_coach_connections set share_workouts=coalesce(p_workouts,false),share_plan=coalesce(p_plan,false),share_readiness=coalesce(p_readiness,false) where id=c.id;
  -- Remove the entire old snapshot immediately. A new snapshot needs explicit publication.
  delete from public.athlete_coach_snapshots where connection_id=c.id;
 elsif p_action = 'revoke' then
  update public.athlete_coach_connections set state='revoked',share_workouts=false,share_plan=false,share_readiness=false where id=c.id;
  delete from public.athlete_coach_snapshots where connection_id=c.id;
  delete from public.athlete_coach_feedback where connection_id=c.id;
 else raise exception 'Action not permitted' using errcode='42501'; end if;
 return c.id;
end $$;
revoke all on function private.manage_athlete_coach(text,uuid,uuid,boolean,boolean,boolean) from public, anon;
grant execute on function private.manage_athlete_coach(text,uuid,uuid,boolean,boolean,boolean) to authenticated;
create function public.manage_athlete_coach(p_action text, p_connection uuid default null, p_coach uuid default null,
 p_workouts boolean default false, p_plan boolean default false, p_readiness boolean default false) returns uuid
language sql security invoker set search_path = '' as $$
 select private.manage_athlete_coach(p_action,p_connection,p_coach,p_workouts,p_plan,p_readiness);
$$;
revoke all on function public.manage_athlete_coach(text,uuid,uuid,boolean,boolean,boolean) from public, anon;
grant execute on function public.manage_athlete_coach(text,uuid,uuid,boolean,boolean,boolean) to authenticated;

create function private.publish_athlete_coach_snapshot(p_connection uuid,p_plan text,p_workouts jsonb,p_readiness integer)
returns void language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); c public.athlete_coach_connections; clean jsonb;
begin
 if actor is null then raise exception 'Sign in required' using errcode='42501'; end if;
 select * into c from public.athlete_coach_connections where id=p_connection for update;
 if not found or actor <> c.athlete_id or c.state <> 'active' or private.is_blocked(c.coach_id)
 then raise exception 'Athlete consent required' using errcode='42501'; end if;
 if p_workouts is not null and (jsonb_typeof(p_workouts) <> 'array' or length(p_workouts::text)>30000)
 then raise exception 'Invalid workout summary'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'title',left(item->>'title',100),'activity',left(item->>'activity',50),
  'date',left(item->>'date',50),'minutes',left(item->>'minutes',20))), '[]'::jsonb)
 into clean from (select value as item from jsonb_array_elements(coalesce(p_workouts,'[]')) limit 20) limited;
 insert into public.athlete_coach_snapshots(connection_id,plan_text,workouts,readiness_score)
 values(c.id,case when c.share_plan then left(p_plan,25000) end,
  case when c.share_workouts then clean end,case when c.share_readiness then p_readiness end)
 on conflict(connection_id) do update set plan_text=excluded.plan_text,workouts=excluded.workouts,
 readiness_score=excluded.readiness_score,updated_at=now();
end $$;
revoke all on function private.publish_athlete_coach_snapshot(uuid,text,jsonb,integer) from public,anon;
grant execute on function private.publish_athlete_coach_snapshot(uuid,text,jsonb,integer) to authenticated;
create function public.publish_athlete_coach_snapshot(p_connection uuid,p_plan text default null,p_workouts jsonb default null,p_readiness integer default null)
returns void language sql security invoker set search_path='' as $$
 select private.publish_athlete_coach_snapshot(p_connection,p_plan,p_workouts,p_readiness);
$$;
revoke all on function public.publish_athlete_coach_snapshot(uuid,text,jsonb,integer) from public,anon;
grant execute on function public.publish_athlete_coach_snapshot(uuid,text,jsonb,integer) to authenticated;

create table public.training_partner_availability (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 starts_at timestamptz not null, ends_at timestamptz not null,
 area text not null check (length(btrim(area)) between 2 and 80),
 sport text not null check (sport in ('running','walking','cycling','strength','swimming')),
 level text not null check (level in ('beginner','intermediate','advanced')),
 enabled boolean not null default false,
 created_at timestamptz not null default now(),
 check(ends_at > starts_at and ends_at <= starts_at + interval '4 hours')
);
create index training_partner_owner_idx on public.training_partner_availability(user_id);
create index training_partner_match_idx on public.training_partner_availability(sport,lower(area),starts_at) where enabled;
alter table public.training_partner_availability enable row level security;
revoke all on public.training_partner_availability from anon,authenticated;
grant select,insert,delete on public.training_partner_availability to authenticated;
create policy partner_read on public.training_partner_availability for select to authenticated using (
 user_id = (select auth.uid()) or (enabled and ends_at > now() and not private.is_blocked(user_id) and private.can_view_profile_card(user_id))
);
create policy partner_insert on public.training_partner_availability for insert to authenticated with check (
 user_id=(select auth.uid()) and starts_at >= now() - interval '5 minutes' and starts_at <= now()+interval '30 days'
);
create policy partner_delete on public.training_partner_availability for delete to authenticated using(user_id=(select auth.uid()));

-- Serialize publication per athlete and bound live availability.
create function private.limit_training_partner_availability() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is not null and auth.uid() <> new.user_id then
  raise exception 'Cannot publish another athlete availability' using errcode='42501';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 761));
 if (select count(*) from public.training_partner_availability where user_id=new.user_id and ends_at>now()) >= 20 then
  raise exception 'Withdraw an existing availability before publishing another';
 end if;
 return new;
end $$;
revoke all on function private.limit_training_partner_availability() from public,anon,authenticated;
create trigger limit_training_partner_availability before insert on public.training_partner_availability
 for each row execute function private.limit_training_partner_availability();
