-- Preserve original ATHLTH verified treadmill interval results. One self-initiated
-- correction is permitted within 24 hours and 15% of measured WORK distance.
create table if not exists public.social_challenge_treadmill_corrections (
    attempt_id uuid primary key references public.social_challenge_attempts(id) on delete cascade,
    challenge_id uuid not null references public.social_challenges(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    original_distance_meters double precision not null check(original_distance_meters > 0),
    corrected_distance_meters double precision not null check(corrected_distance_meters > 0),
    corrected_at timestamptz not null default now()
);
alter table public.social_challenge_treadmill_corrections enable row level security;
create policy "treadmill_correction_visible_to_challenge_members"
on public.social_challenge_treadmill_corrections
for select to authenticated
using (private.can_view_challenge(challenge_id));
revoke all on public.social_challenge_treadmill_corrections from anon, public;
grant select on public.social_challenge_treadmill_corrections to authenticated;

create or replace function public.athlth_correct_treadmill_work_distance(
    p_attempt_id uuid,
    p_corrected_distance_meters double precision
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_user uuid := auth.uid();
    v_attempt public.social_challenge_attempts%rowtype;
    v_rules jsonb;
    v_changed_at timestamptz := clock_timestamp();
begin
    if v_user is null then
        raise exception 'Sign in required' using errcode='28000';
    end if;
    if p_corrected_distance_meters is null or
       not (p_corrected_distance_meters > 0 and p_corrected_distance_meters < 1000000) then
        raise exception 'Invalid treadmill work distance';
    end if;
    select * into v_attempt from public.social_challenge_attempts
    where id=p_attempt_id and user_id=v_user for update;
    if not found then raise exception 'Attempt not found for athlete'; end if;
    select rules into v_rules from public.social_challenges
    where id=v_attempt.challenge_id;
    if v_rules is null or
       v_rules->>'runningFocus' <> 'intervals' or
       v_rules->>'runningVenueRaw' <> 'treadmill' or
       v_rules->>'runningComparison' <> 'mostWorkDistance' or
       v_attempt.verification <> 'athlth' or
       v_attempt.is_eligible is not true or
       v_attempt.source_workout_id is null then
        raise exception 'Only verified treadmill interval work distance is editable';
    end if;
    if v_attempt.ended_at is null or
       v_changed_at < v_attempt.ended_at or
       v_changed_at > v_attempt.ended_at + interval '24 hours' then
        raise exception 'Review window expired';
    end if;
    if v_attempt.distance_meters is null or v_attempt.distance_meters <= 0 or
       p_corrected_distance_meters < v_attempt.distance_meters * 0.85 or
       p_corrected_distance_meters > v_attempt.distance_meters * 1.15 then
        raise exception 'Correction exceeds 15 percent of recorded work distance';
    end if;
    if exists(select 1 from public.social_challenge_treadmill_corrections
              where attempt_id=p_attempt_id) then
        raise exception 'This distance has already been corrected';
    end if;

    insert into public.social_challenge_treadmill_corrections(
        attempt_id,challenge_id,user_id,original_distance_meters,
        corrected_distance_meters,corrected_at
    ) values (
        p_attempt_id,v_attempt.challenge_id,v_user,
        v_attempt.distance_meters,p_corrected_distance_meters,v_changed_at
    );
    update public.social_challenge_attempts
    set distance_meters=p_corrected_distance_meters,
        score=p_corrected_distance_meters,
        detail=to_char(p_corrected_distance_meters / 1000,'FM999990.00') ||
          ' km work · corrected treadmill distance'
    where id=p_attempt_id;

    return jsonb_build_object(
        'attempt_id',p_attempt_id,
        'original_distance_meters',v_attempt.distance_meters,
        'corrected_distance_meters',p_corrected_distance_meters,
        'corrected_at',v_changed_at
    );
end;
$function$;
revoke all on function public.athlth_correct_treadmill_work_distance(uuid,double precision)
from public,anon;
grant execute on function public.athlth_correct_treadmill_work_distance(uuid,double precision)
to authenticated;
