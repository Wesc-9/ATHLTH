-- Keep account-deletion and privacy cleanup fast when the organizer
-- who proposed a replacement deletes their profile.
create index if not exists arena_replacement_proposer_idx
    on public.arena_replacement_proposals(proposed_by);
