-- ATHLTH Arena: advanced rule contract, explicit acceptance and replayable
-- source of truth. Preserves historic tournament results and roster entries.
alter table public.athlth_tournaments
 add column if not exists rotation_mode text not null default 'all'
   check(rotation_mode in ('all','sequence','shuffle')),
 add column if not exists rest_weekdays integer[] not null default '{}',
 add column if not exists proof_mode text not null default 'opponent'
   check(proof_mode in ('opponent','verified')),
 add column if not exists public_results boolean not null default false,
 add column if not exists allow_extensions boolean not null default true,
 add column if not exists rule_version integer not null default 1
   check(rule_version between 1 and 999),
 add column if not exists rules_frozen_at timestamptz,
 add column if not exists tie_break_rule text not null default 'score_difference'
   check(tie_break_rule in ('score_difference','most_wins'));
alter table public.athlth_tournaments
 add constraint athlth_tournament_rest_days_valid
 check(rest_weekdays <@ array[1,2,3,4,5,6,7]::integer[]
       and cardinality(rest_weekdays) < 7);
alter table public.athlth_tournament_entries
 add column if not exists agreed_rule_version integer,
 add column if not exists agreed_rules_at timestamptz;

alter table public.athlth_tournament_rule_proposals
 add column if not exists rotation_mode text not null default 'all'
   check(rotation_mode in ('all','sequence','shuffle')),
 add column if not exists rest_weekdays integer[] not null default '{}',
 add column if not exists proof_mode text not null default 'opponent'
   check(proof_mode in ('opponent','verified')),
 add column if not exists win_points integer not null default 3
   check(win_points between 1 and 10),
 add column if not exists draw_points integer not null default 1
   check(draw_points between 0 and 3);

create or replace function public.athlth_tournament_create_full_rules(
 p_title text, p_format text, p_club uuid, p_season uuid,
 p_group_size integer, p_qualifiers integer, p_invitees uuid[],
 p_warmup_titles text[], p_exercise_mode text, p_exercise_count integer,
 p_proposals_close timestamptz, p_votes_close timestamptz,
 p_approve_player_changes boolean, p_allowed_activities text[],
 p_rules_authority text, p_cadence_days integer, p_completion_hours integer,
 p_rotation_mode text, p_rest_weekdays integer[],
 p_proof_mode text, p_public_results boolean,
 p_allow_extensions boolean, p_win_points integer, p_draw_points integer
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_id uuid;
 v_rest integer[];
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_rotation_mode not in ('all','sequence','shuffle')
    or p_proof_mode not in ('opponent','verified')
    or p_win_points not between 1 and 10
    or p_draw_points not between 0 and least(p_win_points-1,3)
    or p_rest_weekdays is null
    or not (p_rest_weekdays <@ array[1,2,3,4,5,6,7]::integer[])
    or cardinality(p_rest_weekdays)>=7
    or (select count(distinct x) from unnest(p_rest_weekdays) x)
          <> cardinality(p_rest_weekdays) then
   raise exception 'Invalid advanced tournament rules';
 end if;
 v_id:=public.athlth_tournament_create_with_rules(
   p_title,p_format,p_club,p_season,p_group_size,p_qualifiers,p_invitees,
   p_warmup_titles,p_exercise_mode,p_exercise_count,p_proposals_close,
   p_votes_close,p_approve_player_changes,p_allowed_activities,
   p_rules_authority,p_cadence_days,p_completion_hours
 );
 update public.athlth_tournaments
 set rotation_mode=p_rotation_mode,
     rest_weekdays=p_rest_weekdays,proof_mode=p_proof_mode,
     public_results=coalesce(p_public_results,false),
     allow_extensions=coalesce(p_allow_extensions,true),
     win_points=p_win_points,draw_points=p_draw_points
 where id=v_id;
 -- Replace default initial group proposal so the majority vote covers the
 -- whole rule package rather than quietly accepting owner's advanced rules.
 update public.athlth_tournament_rule_proposals
 set rotation_mode=p_rotation_mode,rest_weekdays=p_rest_weekdays,
     proof_mode=p_proof_mode,win_points=p_win_points,
     draw_points=p_draw_points
 where tournament_id=v_id;
 insert into public.athlth_tournament_audit(
   tournament_id,actor_id,event,info
 ) values(v_id,auth.uid(),'advanced_rules_created',
   jsonb_build_object('rotation',p_rotation_mode,
      'rest_weekdays',p_rest_weekdays,'proof_mode',p_proof_mode,
      'public_results',p_public_results,'extensions',p_allow_extensions,
      'win_points',p_win_points,'draw_points',p_draw_points));
 return v_id;
end;
$$;

-- A signed-in athlete explicitly acknowledges the final, current version.
-- This cannot be done on their behalf by the organizer.
create or replace function public.athlth_tournament_acknowledge_rules(
 p_tournament uuid
) returns integer language plpgsql security definer set search_path='' as $$
declare
 v_actor uuid:=auth.uid();
 v_t public.athlth_tournaments%rowtype;
begin
 if v_actor is null then raise exception 'Sign in required'; end if;
 select * into v_t from public.athlth_tournaments
 where id=p_tournament for update;
 if not found or v_t.status<>'inviting'
   or v_t.rules_confirmed_at is null
   or v_t.exercise_selection_finalized_at is null then
   raise exception 'Final rules and exercises must be published first';
 end if;
 update public.athlth_tournament_entries
 set agreed_rule_version=v_t.rule_version,
     agreed_rules_at=clock_timestamp(),
     is_ready=false,ready_at=null
 where tournament_id=p_tournament and user_id=v_actor
   and response='accepted' and removed_at is null;
 if not found then raise exception 'Only an accepted athlete can agree'; end if;
 insert into public.athlth_tournament_audit(
   tournament_id,actor_id,event,info
 ) values(p_tournament,v_actor,'rules_accepted',
   jsonb_build_object('version',v_t.rule_version));
 return v_t.rule_version;
end;
$$;

revoke all on function public.athlth_tournament_create_full_rules(
 text,text,uuid,uuid,integer,integer,uuid[],text[],text,integer,
 timestamptz,timestamptz,boolean,text[],text,integer,integer,
 text,integer[],text,boolean,boolean,integer,integer
) from public,anon;
grant execute on function public.athlth_tournament_create_full_rules(
 text,text,uuid,uuid,integer,integer,uuid[],text[],text,integer,
 timestamptz,timestamptz,boolean,text[],text,integer,integer,
 text,integer[],text,boolean,boolean,integer,integer
) to authenticated;
revoke all on function public.athlth_tournament_acknowledge_rules(uuid)
 from public,anon;
grant execute on function public.athlth_tournament_acknowledge_rules(uuid)
 to authenticated;
-- Legacy full-rule endpoint is internal to create_full_rules: only its
-- definer may invoke it, not client sessions circumventing advanced rules.
revoke execute on function public.athlth_tournament_create_with_rules(
 text,text,uuid,uuid,integer,integer,uuid[],text[],text,integer,
 timestamptz,timestamptz,boolean,text[],text,integer,integer
) from authenticated;
