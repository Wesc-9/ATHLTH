-- Train Together creator improvements:
-- - allow up to 15 open guest spots (16 total including creator)
-- - persist Apple Maps meeting-point address and coordinates privately

alter table public.train_together_posts
  drop constraint if exists train_together_posts_max_guests_check;

alter table public.train_together_posts
  add constraint train_together_posts_max_guests_check
  check (max_guests between 1 and 15);

alter table public.train_together_posts
  drop constraint if exists train_together_posts_accepted_guests_check;

alter table public.train_together_posts
  add constraint train_together_posts_accepted_guests_check
  check (accepted_guests between 0 and 15);

alter table public.train_together_post_meetups
  add column if not exists meeting_address text,
  add column if not exists meeting_latitude double precision,
  add column if not exists meeting_longitude double precision;

alter table public.train_together_post_meetups
  drop constraint if exists train_together_meetups_address_check;

alter table public.train_together_post_meetups
  add constraint train_together_meetups_address_check
  check (
    meeting_address is null
    or char_length(btrim(meeting_address)) <= 400
  );

alter table public.train_together_post_meetups
  drop constraint if exists train_together_meetups_latitude_check;

alter table public.train_together_post_meetups
  add constraint train_together_meetups_latitude_check
  check (
    meeting_latitude is null
    or meeting_latitude between -90 and 90
  );

alter table public.train_together_post_meetups
  drop constraint if exists train_together_meetups_longitude_check;

alter table public.train_together_post_meetups
  add constraint train_together_meetups_longitude_check
  check (
    meeting_longitude is null
    or meeting_longitude between -180 and 180
  );
