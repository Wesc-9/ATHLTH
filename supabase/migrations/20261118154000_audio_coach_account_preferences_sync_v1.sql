-- Account-owned Audio Coach preferences only: no workout GPS or HealthKit samples.
-- One private document per authenticated user, with optimistic revision checks.
create table if not exists public.audio_coach_account_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 1 check (revision > 0),
  body_base64 text not null check (octet_length(body_base64) between 1 and 2000000),
  updated_at timestamptz not null default now()
);

alter table public.audio_coach_account_state enable row level security;
create policy "audio_coach_read_own" on public.audio_coach_account_state
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "audio_coach_create_own" on public.audio_coach_account_state
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "audio_coach_update_own" on public.audio_coach_account_state
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
grant select, insert, update on public.audio_coach_account_state to authenticated;

create or replace function public.save_audio_coach_state(
  p_expected_revision bigint, p_body_base64 text
) returns bigint language plpgsql security invoker set search_path = public
as $$
declare
  actor uuid := (select auth.uid());
  new_revision bigint;
begin
  if actor is null then
    raise exception 'Authenticated account required' using errcode = '28000';
  end if;
  if p_body_base64 is null or octet_length(p_body_base64) not between 1 and 2000000 then
    raise exception 'Audio coach payload exceeds allowed size' using errcode = '22001';
  end if;
  if p_expected_revision = 0 then
    insert into public.audio_coach_account_state(user_id,revision,body_base64)
    values(actor,1,p_body_base64)
    on conflict (user_id) do nothing returning revision into new_revision;
  elsif p_expected_revision > 0 then
    update public.audio_coach_account_state
      set revision = revision + 1,
          body_base64 = p_body_base64,
          updated_at = now()
      where user_id = actor and revision = p_expected_revision
      returning revision into new_revision;
  end if;
  if new_revision is null then
    raise exception 'audio_coach_conflict' using errcode = '40001';
  end if;
  return new_revision;
end;
$$;
revoke execute on function public.save_audio_coach_state(bigint,text) from public;
grant execute on function public.save_audio_coach_state(bigint,text) to authenticated;
