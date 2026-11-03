-- Lightweight, opt-in arrival coordination for in-person Train Together.
-- No location coordinates are tracked or stored.
alter table public.social_workout_participants
    add column if not exists arrival_status text;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'social_workout_participants_arrival_status_check'
          and conrelid = 'public.social_workout_participants'::regclass
    ) then
        alter table public.social_workout_participants
            add constraint social_workout_participants_arrival_status_check
            check (arrival_status is null or
                   arrival_status in ('on_the_way', 'here'));
    end if;
end $$;

comment on column public.social_workout_participants.arrival_status is
    'Optional self-declared arrival status. No GPS or live-location sharing.';
