create or replace function private.normalize_official_weekly_challenge_hero_asset()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, private
as $$
begin
  if new.hero_asset = 'CommunityHero' then
    new.hero_asset := 'TrainHero';
  end if;
  return new;
end;
$$;

drop trigger if exists normalize_official_weekly_challenge_hero_asset
  on public.official_weekly_challenges;

create trigger normalize_official_weekly_challenge_hero_asset
before insert or update of hero_asset
on public.official_weekly_challenges
for each row
execute function private.normalize_official_weekly_challenge_hero_asset();

update public.official_weekly_challenges
set hero_asset = 'TrainHero',
    updated_at = now()
where id = '1885ac60-1fb4-4e84-9f23-c0e4afd79b66'::uuid
  and coalesce(hero_asset, '') = '';