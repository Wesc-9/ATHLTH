alter table public.training_plan_catalog
    add column if not exists catalog_version integer not null default 1;

update public.training_plan_catalog
set workout_pattern = array['walk_run','easy_run','long_run'], catalog_version = 2, updated_at = now()
where slug = 'first-5k';

update public.training_plan_catalog
set workout_pattern = array['easy_run','tempo_run','strength','long_run'], catalog_version = 2, updated_at = now()
where slug = '10k-builder';

update public.training_plan_catalog
set workout_pattern = array['easy_run','strength','tempo_run','long_run'], catalog_version = 2, updated_at = now()
where slug = 'half-marathon-foundation';

update public.training_plan_catalog
set workout_pattern = array['easy_run','strength','interval_run','easy_run','long_run'], catalog_version = 2, updated_at = now()
where slug = 'marathon-build';

update public.training_plan_catalog
set workout_pattern = array['full_body_a','full_body_b','full_body_c'], catalog_version = 2, updated_at = now()
where slug = 'strength-foundations';

update public.training_plan_catalog
set workout_pattern = array['easy_run','full_body_a','tempo_run','full_body_b'], catalog_version = 2, updated_at = now()
where slug = 'hybrid-foundation';
