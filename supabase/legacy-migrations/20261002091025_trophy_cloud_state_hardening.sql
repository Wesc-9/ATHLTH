create table if not exists public.athlth_award_unlocks (
  user_id uuid not null references public.profiles(id) on delete cascade,
  stage_key text not null,
  award_id text not null,
  award_class text not null check (award_class in ('achievement', 'trophy')),
  stage_title text not null,
  title text not null,
  rarity text not null check (rarity in ('core', 'rare', 'epic', 'signature')),
  category text not null,
  verification_source text not null,
  system_image text not null default 'medal.fill',
  unlocked_at timestamptz not null,
  evidence jsonb not null default '{}'::jsonb,
  username_at_unlock text,
  engraving_achievement text,
  engraving_text text,
  engraving_generated_at timestamptz,
  engraving_version integer not null default 1 check (engraving_version >= 1),
  created_at timestamptz not null default now(),
  primary key (user_id, stage_key)
);

create index if not exists athlth_award_unlocks_user_award_idx
  on public.athlth_award_unlocks (user_id, award_id, unlocked_at desc);

alter table public.athlth_award_unlocks enable row level security;

revoke all on table public.athlth_award_unlocks from anon, authenticated;
grant select, insert, update, delete on table public.athlth_award_unlocks to service_role;

create or replace function public.athlth_award_unlocks_immutable_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.user_id is distinct from new.user_id
     or old.stage_key is distinct from new.stage_key
     or old.award_id is distinct from new.award_id
     or old.award_class is distinct from new.award_class
     or old.stage_title is distinct from new.stage_title
     or old.title is distinct from new.title
     or old.rarity is distinct from new.rarity
     or old.category is distinct from new.category
     or old.verification_source is distinct from new.verification_source
     or old.system_image is distinct from new.system_image
     or old.unlocked_at is distinct from new.unlocked_at
     or old.evidence is distinct from new.evidence
     or old.username_at_unlock is distinct from new.username_at_unlock
     or old.created_at is distinct from new.created_at
  then
    raise exception 'ATHLTH award unlock facts are immutable';
  end if;

  return new;
end;
$$;

revoke all on function public.athlth_award_unlocks_immutable_guard() from public, anon, authenticated;

drop trigger if exists athlth_award_unlocks_immutable_guard_trigger
  on public.athlth_award_unlocks;

create trigger athlth_award_unlocks_immutable_guard_trigger
before update on public.athlth_award_unlocks
for each row
execute function public.athlth_award_unlocks_immutable_guard();

create table if not exists public.user_award_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  showcase_ids text[] not null default '{}'::text[]
    check (cardinality(showcase_ids) <= 4),
  updated_at timestamptz not null default now()
);

alter table public.user_award_preferences enable row level security;

revoke all on table public.user_award_preferences from anon, authenticated;
grant select, insert, update, delete on table public.user_award_preferences to service_role;
