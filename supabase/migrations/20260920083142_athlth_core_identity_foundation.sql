-- ATHLTH Development core identity foundation.
-- Applied to project hnkybbzxffvyhzrstqdo on 2026-09-20.
-- Source of truth for profiles, roles, preferences, server-side ATHLTH+ trial,
-- subscription entitlement metadata and notification device registration.

create extension if not exists citext with schema extensions;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username extensions.citext unique,
  display_name text,
  bio text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_format check (
    username is null or (
      char_length(username::text) between 3 and 20
      and username::text ~ '^[a-z0-9_]+$'
    )
  ),
  constraint profiles_display_name_length check (display_name is null or char_length(display_name) <= 80),
  constraint profiles_bio_length check (bio is null or char_length(bio) <= 300)
);

create table public.account_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'user' check (role in ('user', 'admin', 'owner')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  language text not null default 'system',
  measurement_system text not null default 'metric' check (measurement_system in ('metric', 'imperial')),
  appearance text not null default 'system' check (appearance in ('system', 'light', 'dark')),
  profile_visibility text not null default 'friends' check (profile_visibility in ('private', 'friends', 'public')),
  default_activity_visibility text not null default 'friends' check (default_activity_visibility in ('private', 'friends', 'public')),
  share_training_presence boolean not null default true,
  share_routes_by_default boolean not null default false,
  hide_route_start_end boolean not null default true,
  share_heart_rate_by_default boolean not null default false,
  workout_reminders_enabled boolean not null default true,
  friend_activity_notifications_enabled boolean not null default true,
  challenge_notifications_enabled boolean not null default true,
  message_notifications_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_personalization (
  user_id uuid primary key references auth.users(id) on delete cascade,
  primary_goal text,
  interests text[] not null default '{}',
  personalized_offer_consent boolean not null default false,
  consent_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.subscription_entitlements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  tier text not null default 'athlth_plus' check (tier in ('free', 'athlth_plus')),
  status text not null default 'trialing' check (status in ('free', 'trialing', 'active', 'expired', 'revoked')),
  source text not null default 'athlth_trial' check (source in ('athlth_trial', 'app_store', 'admin')),
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  app_store_product_id text,
  app_store_original_transaction_id text,
  app_store_environment text check (app_store_environment is null or app_store_environment in ('sandbox', 'production')),
  current_period_ends_at timestamptz,
  last_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.notification_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  platform text not null default 'ios' check (platform in ('ios', 'watchos')),
  app_bundle_id text not null default 'com.wesc9.athlth',
  apns_environment text not null default 'sandbox' check (apns_environment in ('sandbox', 'production')),
  apns_token text not null,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, device_id, app_bundle_id, apns_environment)
);

create index notification_devices_user_id_idx on public.notification_devices(user_id);

create trigger profiles_set_updated_at before update on public.profiles
for each row execute procedure public.set_updated_at();
create trigger account_roles_set_updated_at before update on public.account_roles
for each row execute procedure public.set_updated_at();
create trigger user_preferences_set_updated_at before update on public.user_preferences
for each row execute procedure public.set_updated_at();
create trigger user_personalization_set_updated_at before update on public.user_personalization
for each row execute procedure public.set_updated_at();
create trigger subscription_entitlements_set_updated_at before update on public.subscription_entitlements
for each row execute procedure public.set_updated_at();
create trigger notification_devices_set_updated_at before update on public.notification_devices
for each row execute procedure public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      nullif(new.raw_user_meta_data ->> 'name', '')
    )
  );
  insert into public.account_roles (user_id, role) values (new.id, 'user');
  insert into public.user_preferences (user_id) values (new.id);
  insert into public.user_personalization (user_id) values (new.id);
  insert into public.subscription_entitlements (
    user_id, tier, status, source, trial_started_at, trial_ends_at
  ) values (
    new.id, 'athlth_plus', 'trialing', 'athlth_trial', now(), now() + interval '7 days'
  );
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public;
revoke execute on function public.handle_new_user() from anon;
revoke execute on function public.handle_new_user() from authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.account_roles enable row level security;
alter table public.user_preferences enable row level security;
alter table public.user_personalization enable row level security;
alter table public.subscription_entitlements enable row level security;
alter table public.notification_devices enable row level security;

create policy "profiles_select_own" on public.profiles for select to authenticated
using ((select auth.uid()) = id);
create policy "profiles_update_own" on public.profiles for update to authenticated
using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy "roles_select_own" on public.account_roles for select to authenticated
using ((select auth.uid()) = user_id);
create policy "preferences_select_own" on public.user_preferences for select to authenticated
using ((select auth.uid()) = user_id);
create policy "preferences_update_own" on public.user_preferences for update to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "personalization_select_own" on public.user_personalization for select to authenticated
using ((select auth.uid()) = user_id);
create policy "personalization_update_own" on public.user_personalization for update to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "entitlements_select_own" on public.subscription_entitlements for select to authenticated
using ((select auth.uid()) = user_id);
create policy "notification_devices_select_own" on public.notification_devices for select to authenticated
using ((select auth.uid()) = user_id);
create policy "notification_devices_insert_own" on public.notification_devices for insert to authenticated
with check ((select auth.uid()) = user_id);
create policy "notification_devices_update_own" on public.notification_devices for update to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "notification_devices_delete_own" on public.notification_devices for delete to authenticated
using ((select auth.uid()) = user_id);

grant select, update on public.profiles to authenticated;
grant select on public.account_roles to authenticated;
grant select, update on public.user_preferences to authenticated;
grant select, update on public.user_personalization to authenticated;
grant select on public.subscription_entitlements to authenticated;
grant select, insert, update, delete on public.notification_devices to authenticated;
