-- Persist presentation choices for the official weekly challenge card.
-- Additive JSONB keeps the appearance model extensible without changing
-- challenge participation/scoring behavior.

alter table public.official_weekly_challenges
add column if not exists appearance jsonb not null default
'{
  "text_color_hex": "#FFFFFF",
  "secondary_text_color_hex": "#FFFFFF",
  "show_text_shadow": true,
  "shadow_opacity": 0.72,
  "show_text_backdrop": true,
  "backdrop_opacity": 0.30,
  "show_image_overlay": false,
  "image_overlay_opacity": 0.22,
  "show_badge": true,
  "show_metadata": true,
  "show_subtitle": true,
  "preserve_original_image_colors": true
}'::jsonb;

comment on column public.official_weekly_challenges.appearance is
'Visual presentation settings for the official weekly challenge Community card.';
