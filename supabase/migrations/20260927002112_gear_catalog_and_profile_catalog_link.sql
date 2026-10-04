create table if not exists public.gear_catalog (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('watch','shoes','headphones','other')),
  brand text not null check (char_length(trim(brand)) between 1 and 80),
  model text not null check (char_length(trim(model)) between 1 and 160),
  variants text[] not null default '{}',
  is_featured boolean not null default false,
  sort_order integer not null default 100,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (category, brand, model)
);

create index if not exists gear_catalog_category_brand_idx
  on public.gear_catalog(category, brand, sort_order, model);

alter table public.gear_catalog enable row level security;

drop policy if exists gear_catalog_read_authenticated on public.gear_catalog;
create policy gear_catalog_read_authenticated
  on public.gear_catalog
  for select
  to authenticated
  using (is_active = true);

drop policy if exists gear_catalog_admin_insert on public.gear_catalog;
create policy gear_catalog_admin_insert
  on public.gear_catalog
  for insert
  to authenticated
  with check (private.is_app_admin());

drop policy if exists gear_catalog_admin_update on public.gear_catalog;
create policy gear_catalog_admin_update
  on public.gear_catalog
  for update
  to authenticated
  using (private.is_app_admin())
  with check (private.is_app_admin());

drop policy if exists gear_catalog_admin_delete on public.gear_catalog;
create policy gear_catalog_admin_delete
  on public.gear_catalog
  for delete
  to authenticated
  using (private.is_app_admin());

alter table public.profile_gear_details
  add column if not exists catalog_item_id uuid
    references public.gear_catalog(id) on delete set null,
  add column if not exists variant_label text;

create index if not exists profile_gear_details_catalog_item_idx
  on public.profile_gear_details(catalog_item_id);

insert into public.gear_catalog
  (category, brand, model, variants, is_featured, sort_order)
values
  ('watch','Apple','Apple Watch Series 12',array['42 mm','46 mm'],true,1),
  ('watch','Apple','Apple Watch Ultra 4',array['49 mm'],true,2),
  ('watch','Apple','Apple Watch SE 3',array[]::text[],true,3),
  ('watch','Apple','Apple Watch Series 11',array['42 mm','46 mm'],false,10),
  ('watch','Apple','Apple Watch Ultra 3',array['49 mm'],false,11),
  ('watch','Apple','Apple Watch Series 10',array['42 mm','46 mm'],false,12),
  ('watch','Apple','Apple Watch Ultra 2',array['49 mm'],false,13),
  ('watch','Apple','Apple Watch SE (2nd generation)',array['40 mm','44 mm'],false,14),
  ('watch','Apple','Apple Watch Series 9',array['41 mm','45 mm'],false,15),
  ('watch','Garmin','Forerunner 965',array[]::text[],true,20),
  ('watch','Garmin','Forerunner 265',array[]::text[],true,21),
  ('watch','Garmin','fēnix 8',array[]::text[],true,22),
  ('watch','Garmin','Venu 3',array[]::text[],false,23),
  ('watch','COROS','PACE 3',array[]::text[],true,30),
  ('watch','COROS','PACE Pro',array[]::text[],true,31),
  ('watch','Polar','Vantage V3',array[]::text[],true,40),
  ('watch','Polar','Pacer Pro',array[]::text[],false,41),
  ('watch','Suunto','Race',array[]::text[],true,50),
  ('watch','Suunto','Vertical',array[]::text[],false,51),
  ('shoes','Nike','Pegasus',array[]::text[],true,100),
  ('shoes','Nike','Vomero',array[]::text[],false,101),
  ('shoes','adidas','Adizero Boston',array[]::text[],true,110),
  ('shoes','ASICS','GEL-NIMBUS',array[]::text[],true,120),
  ('shoes','ASICS','NOVABLAST',array[]::text[],false,121),
  ('shoes','HOKA','Clifton',array[]::text[],true,130),
  ('shoes','HOKA','Mach',array[]::text[],false,131),
  ('shoes','Saucony','Endorphin Speed',array[]::text[],true,140),
  ('shoes','New Balance','Fresh Foam X 1080',array[]::text[],true,150),
  ('headphones','Apple','AirPods Pro',array[]::text[],true,200),
  ('headphones','Apple','AirPods',array[]::text[],true,201),
  ('headphones','Beats','Powerbeats Pro',array[]::text[],true,210),
  ('headphones','Shokz','OpenRun',array[]::text[],true,220)
on conflict (category, brand, model) do update
set variants = excluded.variants,
    is_featured = excluded.is_featured,
    sort_order = excluded.sort_order,
    is_active = true,
    updated_at = now();
