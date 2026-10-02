create table if not exists public.apple_sign_in_tokens (
  user_id uuid primary key references auth.users(id) on delete cascade,
  refresh_token text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.apple_sign_in_tokens enable row level security;

revoke all on table public.apple_sign_in_tokens from anon;
revoke all on table public.apple_sign_in_tokens from authenticated;

comment on table public.apple_sign_in_tokens is
  'Server-only Sign in with Apple refresh tokens used exclusively for Apple authorization revocation during account deletion.';
comment on column public.apple_sign_in_tokens.refresh_token is
  'Sensitive Apple refresh token. Never expose to client roles.';
