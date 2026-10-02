-- ATHLTH 1.5.2: unified workout + exercise catalog foundation.
-- Adds the missing hierarchy:
-- Exercise -> Workout Block -> Workout -> Training Plan.
-- Routes remain optional resources that can be attached to a workout.

create table if not exists public.exercise_catalog (
  id uuid primary key,
  slug text not null unique,
  name text not null,
  summary text not null default '',
  instructions text[] not null default '{}',
  primary_muscles text[] not null default '{}',
  secondary_muscles text[] not null default '{}',
  equipment text[] not null default '{}',
  category text not null default 'functional',
  difficulty text not null default 'All levels',
  source_label text,
  source_url text,
  sort_order integer not null default 100,
  is_published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.exercise_catalog enable row level security;
grant select on public.exercise_catalog to authenticated;

drop policy if exists "Authenticated users can read published exercises"
on public.exercise_catalog;
create policy "Authenticated users can read published exercises"
on public.exercise_catalog
for select
to authenticated
using (is_published = true);

create table if not exists public.workout_template_catalog (
  id uuid primary key,
  slug text not null unique,
  title text not null,
  summary text not null default '',
  category text not null
    check (category in ('running','strength','hybrid','mobility','custom')),
  difficulty text not null default 'All levels',
  estimated_duration_minutes integer,
  tags text[] not null default '{}',
  source_label text,
  source_url text,
  blocks jsonb not null default '[]'::jsonb,
  sort_order integer not null default 100,
  is_published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(blocks) = 'array')
);

alter table public.workout_template_catalog enable row level security;
grant select on public.workout_template_catalog to authenticated;

drop policy if exists "Authenticated users can read published workouts"
on public.workout_template_catalog;
create policy "Authenticated users can read published workouts"
on public.workout_template_catalog
for select
to authenticated
using (is_published = true);

insert into public.exercise_catalog (
  id, slug, name, summary, instructions,
  primary_muscles, secondary_muscles, equipment,
  category, difficulty, source_label, source_url, sort_order
)
values
(
  'c2000000-0000-0000-0000-000000000001',
  'ski-erg',
  'SkiErg',
  'Full-body ski-ergometer station focused on sustained pulling power and aerobic output.',
  array['Stand tall with the handles overhead.','Drive the handles down using lats, core and a small hip hinge.','Return smoothly and keep a repeatable rhythm.'],
  array['Back','Core'],
  array['Shoulders','Arms','Glutes'],
  array['SkiErg'],
  'cardio',
  'All levels',
  'ATHLTH · HYROX station',
  'https://hyrox.com/the-fitness-race/',
  10
),
(
  'c2000000-0000-0000-0000-000000000002',
  'sled-push',
  'Sled Push',
  'Heavy horizontal push performed over a prescribed distance.',
  array['Keep the torso braced and hands fixed on the sled.','Drive through the floor with short powerful steps.','Maintain control through every lane or turn.'],
  array['Quads','Glutes'],
  array['Calves','Core'],
  array['Sled'],
  'strength-endurance',
  'Intermediate',
  'ATHLTH · HYROX station',
  'https://hyrox.com/the-fitness-race/',
  20
),
(
  'c2000000-0000-0000-0000-000000000003',
  'sled-pull',
  'Sled Pull',
  'Rope sled pull combining posterior-chain, back and grip endurance.',
  array['Take tension in the rope before pulling.','Use strong arm pulls while moving backward under control.','Keep the torso braced and the rope clear of the feet.'],
  array['Back','Glutes'],
  array['Biceps','Core','Hamstrings'],
  array['Sled','Rope'],
  'strength-endurance',
  'Intermediate',
  'ATHLTH · HYROX station',
  'https://hyrox.com/the-fitness-race/',
  30
),
(
  'c2000000-0000-0000-0000-000000000004',
  'burpee-broad-jump',
  'Burpee Broad Jump',
  'Chest-to-floor burpee followed by a two-foot broad jump repeated for distance.',
  array['Lower the chest to the floor.','Stand or step forward into a stable takeoff.','Jump forward with both feet and repeat.'],
  array['Full Body'],
  array['Quads','Glutes','Chest','Core'],
  array['Bodyweight'],
  'conditioning',
  'Intermediate',
  'ATHLTH · HYROX station',
  'https://hyrox.com/the-fitness-race/',
  40
),
(
  'c2000000-0000-0000-0000-000000000005',
  'rowing-erg',
  'Rowing',
  'Indoor rowing station performed for distance.',
  array['Drive with the legs first.','Open the hips and finish with the arms.','Recover arms, hips, then knees in a smooth sequence.'],
  array['Back','Quads'],
  array['Glutes','Hamstrings','Arms','Core'],
  array['RowErg'],
  'cardio',
  'All levels',
  'ATHLTH · HYROX station',
  'https://hyrox.com/the-fitness-race/',
  50
),
(
  'c2000000-0000-0000-0000-000000000006',
  'farmers-carry',
  'Farmers Carry',
  'Loaded carry with one implement in each hand.',
  array['Stand tall with one weight in each hand.','Brace the trunk and keep shoulders stable.','Walk quickly without letting the weights swing.'],
  array['Forearms','Core'],
  array['Upper Back','Shoulders','Glutes'],
  array['Kettlebells','Dumbbells'],
  'carry',
  'All levels',
  'ATHLTH · HYROX station',
  'https://hyrox.com/the-fitness-race/',
  60
),
(
  'c2000000-0000-0000-0000-000000000007',
  'sandbag-walking-lunge',
  'Sandbag Walking Lunge',
  'Alternating walking lunges performed while carrying a sandbag.',
  array['Place the sandbag securely across the shoulders.','Step forward and lower the rear knee under control.','Drive through the front foot and alternate legs.'],
  array['Quads','Glutes'],
  array['Hamstrings','Core'],
  array['Sandbag'],
  'strength-endurance',
  'Intermediate',
  'ATHLTH · HYROX station',
  'https://hyrox.com/the-fitness-race/',
  70
),
(
  'c2000000-0000-0000-0000-000000000008',
  'wall-ball',
  'Wall Ball',
  'Squat-to-throw movement using a medicine ball and wall target.',
  array['Hold the ball at chest height.','Squat under control to the required depth.','Stand powerfully and throw the ball to the target.','Receive the ball and flow directly into the next repetition.'],
  array['Quads','Glutes'],
  array['Shoulders','Core'],
  array['Medicine Ball','Wall Target'],
  'conditioning',
  'Intermediate',
  'ATHLTH · HYROX station',
  'https://hyrox.com/the-fitness-race/',
  80
),
(
  'c2000000-0000-0000-0000-000000000009',
  'stationary-lunge',
  'Stationary Lunge',
  'Alternating in-place lunges for repetitions.',
  array['Stand tall and brace the trunk.','Step into a lunge and lower the rear knee toward the floor.','Return to standing and alternate sides.'],
  array['Quads','Glutes'],
  array['Hamstrings','Core'],
  array['Bodyweight'],
  'strength-endurance',
  'All levels',
  'ATHLTH · HYROX PFT',
  'https://register.hyrox.com/event/hyrox-pft---new-york/',
  90
),
(
  'c2000000-0000-0000-0000-000000000010',
  'hand-release-push-up',
  'Hand-Release Push-Up',
  'Push-up variation with a brief hand release at the bottom position.',
  array['Lower the chest fully to the floor.','Briefly lift both hands clear of the floor.','Replace the hands and press back to a strong plank.'],
  array['Chest','Triceps'],
  array['Shoulders','Core'],
  array['Bodyweight'],
  'strength-endurance',
  'All levels',
  'ATHLTH · HYROX PFT',
  'https://register.hyrox.com/event/hyrox-pft---new-york/',
  100
)
on conflict (id) do update set
  slug = excluded.slug,
  name = excluded.name,
  summary = excluded.summary,
  instructions = excluded.instructions,
  primary_muscles = excluded.primary_muscles,
  secondary_muscles = excluded.secondary_muscles,
  equipment = excluded.equipment,
  category = excluded.category,
  difficulty = excluded.difficulty,
  source_label = excluded.source_label,
  source_url = excluded.source_url,
  sort_order = excluded.sort_order,
  is_published = true,
  updated_at = now();

insert into public.workout_template_catalog (
  id, slug, title, summary, category, difficulty,
  estimated_duration_minutes, tags, source_label, source_url,
  blocks, sort_order
)
values
(
  'c3000000-0000-0000-0000-000000000001',
  'hyrox-full-race-simulation',
  'HYROX Full Race Simulation',
  'Full race-order simulation: eight 1 km runs alternating with the eight HYROX stations.',
  'hybrid',
  'Advanced',
  90,
  array['hyrox','hybrid','race-simulation','running','functional'],
  'HYROX official race format',
  'https://hyrox.com/the-fitness-race/',
  '[
    {"sequence":1,"kind":"run","title":"Run 1","distance_meters":1000},
    {"sequence":2,"kind":"exercise","title":"SkiErg","exercise_slug":"ski-erg","distance_meters":1000},
    {"sequence":3,"kind":"run","title":"Run 2","distance_meters":1000},
    {"sequence":4,"kind":"exercise","title":"Sled Push","exercise_slug":"sled-push","distance_meters":50,"load_note":"Use your division race load"},
    {"sequence":5,"kind":"run","title":"Run 3","distance_meters":1000},
    {"sequence":6,"kind":"exercise","title":"Sled Pull","exercise_slug":"sled-pull","distance_meters":50,"load_note":"Use your division race load"},
    {"sequence":7,"kind":"run","title":"Run 4","distance_meters":1000},
    {"sequence":8,"kind":"exercise","title":"Burpee Broad Jumps","exercise_slug":"burpee-broad-jump","distance_meters":80},
    {"sequence":9,"kind":"run","title":"Run 5","distance_meters":1000},
    {"sequence":10,"kind":"exercise","title":"Row","exercise_slug":"rowing-erg","distance_meters":1000},
    {"sequence":11,"kind":"run","title":"Run 6","distance_meters":1000},
    {"sequence":12,"kind":"exercise","title":"Farmers Carry","exercise_slug":"farmers-carry","distance_meters":200,"load_note":"Use your division race load"},
    {"sequence":13,"kind":"run","title":"Run 7","distance_meters":1000},
    {"sequence":14,"kind":"exercise","title":"Sandbag Lunges","exercise_slug":"sandbag-walking-lunge","distance_meters":100,"load_note":"Use your division race load"},
    {"sequence":15,"kind":"run","title":"Run 8","distance_meters":1000},
    {"sequence":16,"kind":"exercise","title":"Wall Balls","exercise_slug":"wall-ball","repetitions":100,"load_note":"Use your division race ball"}
  ]'::jsonb,
  10
),
(
  'c3000000-0000-0000-0000-000000000002',
  'hyrox-half-simulation',
  'HYROX Half Simulation',
  'A shorter race-order session using 500 m runs and approximately half station volume.',
  'hybrid',
  'Intermediate',
  50,
  array['hyrox','hybrid','simulation','running','functional'],
  'ATHLTH adaptation of HYROX race format',
  'https://hyrox.com/the-fitness-race/',
  '[
    {"sequence":1,"kind":"run","title":"Run 1","distance_meters":500},
    {"sequence":2,"kind":"exercise","title":"SkiErg","exercise_slug":"ski-erg","distance_meters":500},
    {"sequence":3,"kind":"run","title":"Run 2","distance_meters":500},
    {"sequence":4,"kind":"exercise","title":"Sled Push","exercise_slug":"sled-push","distance_meters":25,"load_note":"Use a controlled training load"},
    {"sequence":5,"kind":"run","title":"Run 3","distance_meters":500},
    {"sequence":6,"kind":"exercise","title":"Sled Pull","exercise_slug":"sled-pull","distance_meters":25,"load_note":"Use a controlled training load"},
    {"sequence":7,"kind":"run","title":"Run 4","distance_meters":500},
    {"sequence":8,"kind":"exercise","title":"Burpee Broad Jumps","exercise_slug":"burpee-broad-jump","distance_meters":40},
    {"sequence":9,"kind":"run","title":"Run 5","distance_meters":500},
    {"sequence":10,"kind":"exercise","title":"Row","exercise_slug":"rowing-erg","distance_meters":500},
    {"sequence":11,"kind":"run","title":"Run 6","distance_meters":500},
    {"sequence":12,"kind":"exercise","title":"Farmers Carry","exercise_slug":"farmers-carry","distance_meters":100,"load_note":"Use a controlled training load"},
    {"sequence":13,"kind":"run","title":"Run 7","distance_meters":500},
    {"sequence":14,"kind":"exercise","title":"Sandbag Lunges","exercise_slug":"sandbag-walking-lunge","distance_meters":50,"load_note":"Use a controlled training load"},
    {"sequence":15,"kind":"run","title":"Run 8","distance_meters":500},
    {"sequence":16,"kind":"exercise","title":"Wall Balls","exercise_slug":"wall-ball","repetitions":50,"load_note":"Use a controlled training load"}
  ]'::jsonb,
  20
),
(
  'c3000000-0000-0000-0000-000000000003',
  'hyrox-pft',
  'HYROX PFT',
  'Official HYROX Physical Fitness Test performed for time.',
  'hybrid',
  'All levels',
  35,
  array['hyrox','pft','fitness-test','hybrid'],
  'HYROX PFT',
  'https://register.hyrox.com/event/hyrox-pft---new-york/',
  '[
    {"sequence":1,"kind":"run","title":"Run","distance_meters":1000},
    {"sequence":2,"kind":"exercise","title":"Burpee Broad Jumps","exercise_slug":"burpee-broad-jump","repetitions":50},
    {"sequence":3,"kind":"exercise","title":"Stationary Lunges","exercise_slug":"stationary-lunge","repetitions":100},
    {"sequence":4,"kind":"exercise","title":"Row / Run","exercise_slug":"rowing-erg","distance_meters":1000,"notes":"Use the rower, or run if the rower option is unavailable."},
    {"sequence":5,"kind":"exercise","title":"Hand-Release Push-Ups","exercise_slug":"hand-release-push-up","repetitions":30},
    {"sequence":6,"kind":"exercise","title":"Wall Balls","exercise_slug":"wall-ball","repetitions":100,"load_note":"6 kg / 4 kg as specified by the HYROX PFT"}
  ]'::jsonb,
  30
),
(
  'c3000000-0000-0000-0000-000000000004',
  'hyrox-compromised-800s',
  'HYROX Compromised 800s',
  'Four 800 m runs paired with stations to practise running while carrying fatigue.',
  'hybrid',
  'Intermediate',
  45,
  array['hyrox','hybrid','intervals','compromised-running'],
  'ATHLTH training adaptation',
  'https://hyrox.com/the-fitness-race/',
  '[
    {"sequence":1,"kind":"run","title":"800 m Run","distance_meters":800},
    {"sequence":2,"kind":"exercise","title":"SkiErg","exercise_slug":"ski-erg","distance_meters":500},
    {"sequence":3,"kind":"run","title":"800 m Run","distance_meters":800},
    {"sequence":4,"kind":"exercise","title":"Sled Push","exercise_slug":"sled-push","distance_meters":25,"load_note":"Moderate-heavy training load"},
    {"sequence":5,"kind":"run","title":"800 m Run","distance_meters":800},
    {"sequence":6,"kind":"exercise","title":"Row","exercise_slug":"rowing-erg","distance_meters":500},
    {"sequence":7,"kind":"run","title":"800 m Run","distance_meters":800},
    {"sequence":8,"kind":"exercise","title":"Wall Balls","exercise_slug":"wall-ball","repetitions":50}
  ]'::jsonb,
  40
),
(
  'c3000000-0000-0000-0000-000000000005',
  'hyrox-density',
  'HYROX Density',
  '400 m running before every station with reduced station volume for a dense race-specific session.',
  'hybrid',
  'Intermediate',
  55,
  array['hyrox','hybrid','density','stations'],
  'ATHLTH training adaptation',
  'https://hyrox.com/the-fitness-race/',
  '[
    {"sequence":1,"kind":"run","title":"Run 1","distance_meters":400},
    {"sequence":2,"kind":"exercise","title":"SkiErg","exercise_slug":"ski-erg","distance_meters":500},
    {"sequence":3,"kind":"run","title":"Run 2","distance_meters":400},
    {"sequence":4,"kind":"exercise","title":"Sled Push","exercise_slug":"sled-push","distance_meters":25,"load_note":"Training load"},
    {"sequence":5,"kind":"run","title":"Run 3","distance_meters":400},
    {"sequence":6,"kind":"exercise","title":"Sled Pull","exercise_slug":"sled-pull","distance_meters":25,"load_note":"Training load"},
    {"sequence":7,"kind":"run","title":"Run 4","distance_meters":400},
    {"sequence":8,"kind":"exercise","title":"Burpee Broad Jumps","exercise_slug":"burpee-broad-jump","distance_meters":40},
    {"sequence":9,"kind":"run","title":"Run 5","distance_meters":400},
    {"sequence":10,"kind":"exercise","title":"Row","exercise_slug":"rowing-erg","distance_meters":500},
    {"sequence":11,"kind":"run","title":"Run 6","distance_meters":400},
    {"sequence":12,"kind":"exercise","title":"Farmers Carry","exercise_slug":"farmers-carry","distance_meters":100,"load_note":"Training load"},
    {"sequence":13,"kind":"run","title":"Run 7","distance_meters":400},
    {"sequence":14,"kind":"exercise","title":"Sandbag Lunges","exercise_slug":"sandbag-walking-lunge","distance_meters":50,"load_note":"Training load"},
    {"sequence":15,"kind":"run","title":"Run 8","distance_meters":400},
    {"sequence":16,"kind":"exercise","title":"Wall Balls","exercise_slug":"wall-ball","repetitions":50}
  ]'::jsonb,
  50
),
(
  'c3000000-0000-0000-0000-000000000006',
  'hyrox-sled-carry-engine',
  'HYROX Sled & Carry Engine',
  'Strength-endurance session focused on sleds, carries and controlled running.',
  'hybrid',
  'Intermediate',
  40,
  array['hyrox','hybrid','sled','carry','strength-endurance'],
  'ATHLTH training adaptation',
  'https://hyrox.com/the-fitness-race/',
  '[
    {"sequence":1,"kind":"run","title":"Easy Run","distance_meters":800},
    {"sequence":2,"kind":"exercise","title":"Sled Push","exercise_slug":"sled-push","distance_meters":25,"load_note":"Moderate-heavy training load"},
    {"sequence":3,"kind":"exercise","title":"Sled Pull","exercise_slug":"sled-pull","distance_meters":25,"load_note":"Moderate-heavy training load"},
    {"sequence":4,"kind":"run","title":"Steady Run","distance_meters":800},
    {"sequence":5,"kind":"exercise","title":"Farmers Carry","exercise_slug":"farmers-carry","distance_meters":200,"load_note":"Challenging but unbroken if possible"},
    {"sequence":6,"kind":"exercise","title":"Sandbag Lunges","exercise_slug":"sandbag-walking-lunge","distance_meters":50,"load_note":"Controlled training load"},
    {"sequence":7,"kind":"run","title":"Finish Run","distance_meters":800}
  ]'::jsonb,
  60
)
on conflict (id) do update set
  slug = excluded.slug,
  title = excluded.title,
  summary = excluded.summary,
  category = excluded.category,
  difficulty = excluded.difficulty,
  estimated_duration_minutes = excluded.estimated_duration_minutes,
  tags = excluded.tags,
  source_label = excluded.source_label,
  source_url = excluded.source_url,
  blocks = excluded.blocks,
  sort_order = excluded.sort_order,
  is_published = true,
  updated_at = now();
