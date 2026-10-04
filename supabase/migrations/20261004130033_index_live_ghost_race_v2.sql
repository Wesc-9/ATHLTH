create index if not exists live_ghost_race_participants_user_idx
  on public.live_ghost_race_participants (user_id);

create index if not exists live_ghost_race_rooms_winner_idx
  on public.live_ghost_race_rooms (winner_id)
  where winner_id is not null;
