alter table public.athlth_tournaments
 add column if not exists planned_starts_at timestamptz,
 add column if not exists release_mode text not null default 'interval' check (release_mode in ('interval','everyone_finished')),
 add column if not exists release_every integer not null default 7 check (release_every between 1 and 10080),
 add column if not exists release_unit text not null default 'day' check (release_unit in ('minute','hour','day','month')),
 add column if not exists invitation_permission text not null default 'admin' check (invitation_permission in ('admin','participants')),
 add column if not exists join_approval text not null default 'admin' check (join_approval in ('open','participants','admin')),
 add column if not exists allowed_actions text not null default '',
 add column if not exists prohibited_actions text not null default '',
 add column if not exists prize_first text not null default '',
 add column if not exists prize_second text not null default '',
 add column if not exists prize_third text not null default '',
 add column if not exists loser_consequence text not null default '';
