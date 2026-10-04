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

  if old.engraving_achievement is not null
     or old.engraving_text is not null
     or old.engraving_generated_at is not null
  then
    if old.engraving_achievement is distinct from new.engraving_achievement
       or old.engraving_text is distinct from new.engraving_text
       or old.engraving_generated_at is distinct from new.engraving_generated_at
       or old.engraving_version is distinct from new.engraving_version
    then
      raise exception 'ATHLTH trophy engraving is frozen once generated';
    end if;
  else
    if (new.engraving_achievement is null) <>
       (new.engraving_text is null)
       or (new.engraving_achievement is null) <>
          (new.engraving_generated_at is null)
    then
      raise exception 'ATHLTH trophy engraving must be written atomically';
    end if;
  end if;

  return new;
end;
$$;
