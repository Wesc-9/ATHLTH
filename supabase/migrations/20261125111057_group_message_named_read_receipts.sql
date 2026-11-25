create table private.athlth_group_message_reads (
 conversation_kind text not null check(conversation_kind in ('club','arena','tournament')),
 message_id uuid not null,
 reader_id uuid not null references auth.users(id) on delete cascade,
 read_at timestamptz not null default now(),
 share_at_read boolean not null,
 primary key(conversation_kind,message_id,reader_id)
);
alter table private.athlth_group_message_reads enable row level security;
revoke all on private.athlth_group_message_reads from public,anon,authenticated;
-- Only messages from a group the current caller is authorized to see.
create function private.athlth_group_receipt_candidates(p_kind text,p_ids uuid[])
returns table(message_id uuid,sender_id uuid)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or p_ids is null or cardinality(p_ids)>300 then raise exception 'Invalid receipt request' using errcode='42501'; end if;
 case p_kind
 when 'club' then return query select m.id,m.sender_id from public.community_group_messages m
  where m.id=any(p_ids) and m.deleted_at is null and private.is_community_group_member(m.group_id,auth.uid());
 when 'arena' then return query select m.id,m.sender_id from public.arena_series_messages m
  where m.id=any(p_ids) and exists(select 1 from public.arena_series_members a where a.series_id=m.series_id and a.user_id=auth.uid() and a.response='accepted');
 when 'tournament' then return query select m.id,m.author_id from public.athlth_tournament_lobby_messages m
  where m.id=any(p_ids) and m.kind<>'system' and private.athlth_tournament_is_entrant(m.tournament_id)
  and exists(select 1 from public.athlth_tournament_entries e where e.tournament_id=m.tournament_id and e.user_id=auth.uid() and e.removed_at is null and e.response in ('accepted','invited'));
 else raise exception 'Unsupported conversation kind' using errcode='22023';
 end case;
end; $$;
revoke all on function private.athlth_group_receipt_candidates(text,uuid[]) from public,anon,authenticated;

create function private.athlth_group_message_receipts(p_kind text,p_ids uuid[],p_mark_read boolean default true)
returns table(message_id uuid,reader_name text)
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); sharing boolean;
begin
 if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 sharing:=coalesce((select p.share_receipts from private.athlth_message_receipt_preferences p where p.user_id=uid),true);
 if p_mark_read then
  insert into private.athlth_group_message_reads(conversation_kind,message_id,reader_id,share_at_read)
  select p_kind,m.message_id,uid,sharing from private.athlth_group_receipt_candidates(p_kind,p_ids) m
  where m.sender_id is not null and m.sender_id<>uid
  on conflict on constraint athlth_group_message_reads_pkey do nothing;
 end if;
 return query select r.message_id,coalesce(nullif(p.display_name,''),nullif(p.username::text,''),'Participant')
 from private.athlth_group_receipt_candidates(p_kind,p_ids) m
 join private.athlth_group_message_reads r on r.message_id=m.message_id and r.conversation_kind=p_kind
 join public.profiles p on p.id=r.reader_id
 left join private.athlth_message_receipt_preferences pref on pref.user_id=r.reader_id
 where m.sender_id=uid and r.share_at_read and coalesce(pref.share_receipts,true)
 order by r.read_at,r.reader_id;
end; $$;
revoke all on function private.athlth_group_message_receipts(text,uuid[],boolean) from public,anon;
grant execute on function private.athlth_group_message_receipts(text,uuid[],boolean) to authenticated;
create function public.athlth_group_message_receipts(p_kind text,p_ids uuid[],p_mark_read boolean default true)
returns table(message_id uuid,reader_name text)
language sql security invoker set search_path='' as $$
 select * from private.athlth_group_message_receipts(p_kind,p_ids,p_mark_read);
$$;
revoke all on function public.athlth_group_message_receipts(text,uuid[],boolean) from public,anon;
grant execute on function public.athlth_group_message_receipts(text,uuid[],boolean) to authenticated;
