-- Activity and cadence contract for tournaments.
alter table public.athlth_tournaments
 add column if not exists allowed_activities text[] not null default array['strength']::text[],
 add column if not exists rules_authority text not null default 'owner'
    check(rules_authority in ('owner','group')),
 add column if not exists cadence_days integer not null default 7
    check(cadence_days between 1 and 28),
 add column if not exists completion_hours integer not null default 48
    check(completion_hours between 1 and 672),
 add column if not exists rules_confirmed_at timestamptz;
alter table public.athlth_tournaments
 add constraint athlth_allowed_activities_valid check(
  cardinality(allowed_activities) between 1 and 6 and
  allowed_activities <@ array['running','strength','cycling','walking','swimming','hiking']::text[]
 );
update public.athlth_tournaments
 set rules_confirmed_at=coalesce(rules_confirmed_at,created_at)
 where rules_authority='owner';

create table if not exists public.athlth_tournament_activity_templates(
 id uuid primary key default gen_random_uuid(),
 slug text not null unique,
 title text not null check(length(title) between 3 and 100),
 activity_type text not null check(activity_type in ('running','strength','cycling','walking','swimming','hiking')),
 metric text not null check(metric in ('distance','duration','repetitions','time')),
 target_value numeric(10,2),
 is_active boolean not null default true
);
insert into public.athlth_tournament_activity_templates(slug,title,activity_type,metric,target_value) values
('run-3km','Løp 3 km','running','distance',3000),
('run-5km','Løp 5 km','running','distance',5000),
('run-10km','Løp 10 km','running','distance',10000),
('run-30min','Løp lengst på 30 min','running','duration',1800),
('cycle-10km','Sykkel 10 km','cycling','distance',10000),
('cycle-20km','Sykkel 20 km','cycling','distance',20000),
('cycle-40km','Sykkel 40 km','cycling','distance',40000),
('cycle-45min','Sykkel lengst på 45 min','cycling','duration',2700),
('strength-pushups','Armhevinger – flest repetisjoner','strength','repetitions',null),
('strength-squats','Knebøy – flest repetisjoner','strength','repetitions',null),
('strength-plank','Planke – lengst tid','strength','time',null),
('strength-burpees','Burpees – flest repetisjoner','strength','repetitions',null),
('walk-5km','Gå 5 km','walking','distance',5000),
('walk-10km','Gå 10 km','walking','distance',10000),
('swim-500m','Svøm 500 m','swimming','distance',500),
('swim-1000m','Svøm 1000 m','swimming','distance',1000),
('hike-5km','Tur 5 km','hiking','distance',5000),
('hike-10km','Tur 10 km','hiking','distance',10000)
on conflict (slug) do nothing;

alter table public.athlth_tournament_exercise_candidates
 add column if not exists activity_template_id uuid
 references public.athlth_tournament_activity_templates(id);
alter table public.athlth_tournament_exercise_candidates alter column exercise_id drop not null;
alter table public.athlth_tournament_exercise_candidates
 add constraint athlth_candidate_exercise_source_valid check(
  num_nonnulls(exercise_id,activity_template_id)=1
 );
create unique index if not exists athlth_candidate_template_unique
 on public.athlth_tournament_exercise_candidates(tournament_id,activity_template_id)
 where activity_template_id is not null;

alter table public.athlth_tournament_activity_templates enable row level security;
create policy "signed_in_templates_read" on public.athlth_tournament_activity_templates
 for select to authenticated using (is_active);
revoke all on public.athlth_tournament_activity_templates from anon,authenticated,public;
grant select on public.athlth_tournament_activity_templates to authenticated;

create table if not exists public.athlth_tournament_rule_proposals(
 id uuid primary key default gen_random_uuid(),
 tournament_id uuid not null references public.athlth_tournaments(id) on delete cascade,
 proposer_id uuid not null references public.profiles(id),
 allowed_activities text[] not null,
 cadence_days integer not null check(cadence_days between 1 and 28),
 completion_hours integer not null check(completion_hours between 1 and 672),
 created_at timestamptz not null default now(),
 check(cardinality(allowed_activities) between 1 and 6 and
  allowed_activities <@ array['running','strength','cycling','walking','swimming','hiking']::text[])
);
create table if not exists public.athlth_tournament_rule_votes(
 tournament_id uuid not null references public.athlth_tournaments(id) on delete cascade,
 voter_id uuid not null references public.profiles(id),
 proposal_id uuid not null references public.athlth_tournament_rule_proposals(id) on delete cascade,
 voted_at timestamptz not null default now(),
 primary key(tournament_id,voter_id)
);
create index if not exists athlth_rules_proposals_tournament
 on public.athlth_tournament_rule_proposals(tournament_id,created_at);
alter table public.athlth_tournament_rule_proposals enable row level security;
alter table public.athlth_tournament_rule_votes enable row level security;
create policy "entrant_read_rule_proposals" on public.athlth_tournament_rule_proposals
 for select to authenticated
 using(private.athlth_tournament_is_entrant(tournament_id));
create policy "entrant_read_rule_votes" on public.athlth_tournament_rule_votes
 for select to authenticated
 using(private.athlth_tournament_is_entrant(tournament_id));
revoke all on public.athlth_tournament_rule_proposals,
 public.athlth_tournament_rule_votes from anon,authenticated,public;
grant select on public.athlth_tournament_rule_proposals,
 public.athlth_tournament_rule_votes to authenticated;
