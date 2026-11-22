insert into public.athlth_tournament_activity_templates
 (slug,title,activity_type,metric,target_value,is_active)
select items.slug,items.title,'running',items.metric,items.target_value,true
from (values
 ('sprint-100m','Sprint 100 m','distance',100::numeric),
 ('sprint-200m','Sprint 200 m','distance',200::numeric),
 ('sprint-400m','Sprint 400 m','distance',400::numeric),
 ('sprint-60s','Sprint – lengst på 60 sek','duration',60::numeric)
) as items(slug,title,metric,target_value)
where not exists(select 1 from public.athlth_tournament_activity_templates existing
 where existing.slug=items.slug);