-- Add explicit owner-supplied route metadata.
-- Existing routes remain unchanged, with no inferred surface percentages.
-- Route RLS policies continue to govern both new fields.
alter table public.community_routes
    add column if not exists tags text[] not null default array[]::text[],
    add column if not exists surface_percentages jsonb not null default '{}'::jsonb;

comment on column public.community_routes.tags is
    'Optional route-owner supplied searchable tags; visibility follows community_routes RLS.';
comment on column public.community_routes.surface_percentages is
    'Route-owner supplied map from surface type to integer percent. Unspecified part is unknown; never inferred.';

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'community_routes_surface_percentages_object'
          and conrelid = 'public.community_routes'::regclass
    ) then
        alter table public.community_routes
            add constraint community_routes_surface_percentages_object
            check (jsonb_typeof(surface_percentages) = 'object');
    end if;
end $$;
