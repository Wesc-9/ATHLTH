-- Supabase Realtime sends row changes only to subscribed users who pass
-- the existing Arena RLS policies. Realtime is a presentation layer;
-- the database remains the source of truth for results and permissions.
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'arena_series_messages',
    'arena_series',
    'arena_round_results',
    'arena_round_result_votes',
    'arena_replacement_proposals',
    'arena_replacement_votes'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public'
        and tablename=v_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I',v_table);
    end if;
  end loop;
end $$;
