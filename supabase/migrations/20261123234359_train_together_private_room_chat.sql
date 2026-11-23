create table public.social_workout_room_messages (
  id uuid primary key default gen_random_uuid(),
  source_workout_id uuid not null references public.social_workout_draft_lobbies(source_workout_id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index social_workout_room_messages_source_time_idx on public.social_workout_room_messages(source_workout_id, created_at desc, id);
alter table public.social_workout_room_messages enable row level security;
revoke all on public.social_workout_room_messages from public, anon, authenticated;
grant select on public.social_workout_room_messages to authenticated;
grant insert (id, source_workout_id, sender_id, body) on public.social_workout_room_messages to authenticated;
create policy room_messages_members_read on public.social_workout_room_messages for select to authenticated using (
  exists (select 1 from public.social_workout_draft_lobbies d
    where d.source_workout_id = social_workout_room_messages.source_workout_id
      and (select auth.uid()) in (d.owner_id, d.partner_id)
      and not private.is_blocked(case when (select auth.uid()) = d.owner_id then d.partner_id else d.owner_id end))
);
create policy room_messages_members_send on public.social_workout_room_messages for insert to authenticated with check (
  sender_id = (select auth.uid()) and exists (
    select 1 from public.social_workout_draft_lobbies d
      where d.source_workout_id = social_workout_room_messages.source_workout_id
      and d.cancelled_at is null
      and (select auth.uid()) in (d.owner_id, d.partner_id)
      and not private.is_blocked(case when (select auth.uid()) = d.owner_id then d.partner_id else d.owner_id end))
);
