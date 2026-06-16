alter table public.linked_oauth_accounts
  add column if not exists provider_user_id text;

comment on column public.linked_oauth_accounts.provider_user_id is
  'Provider account id used to route Strava/WHOOP webhooks. OAuth token payload remains encrypted.';

create index if not exists linked_oauth_accounts_provider_user_idx
  on public.linked_oauth_accounts (provider, provider_user_id)
  where provider_user_id is not null;

create table if not exists public.external_webhook_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null check (provider in ('strava', 'whoop')),
  provider_user_id text not null,
  provider_object_id text not null,
  event_type text not null,
  aspect_type text,
  object_type text,
  updates jsonb not null default '{}'::jsonb,
  trace_id text,
  payload jsonb not null default '{}'::jsonb,
  processed_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table public.external_webhook_events is
  'Inbound Strava/WHOOP webhook notifications routed to Mangox users for app-side refresh.';

alter table public.external_webhook_events enable row level security;
alter table public.external_webhook_events force row level security;

create policy external_webhook_events_select on public.external_webhook_events
  for select
  using (auth.uid() = user_id);

create policy external_webhook_events_update on public.external_webhook_events
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy external_webhook_events_delete on public.external_webhook_events
  for delete
  using (auth.uid() = user_id);

create index if not exists external_webhook_events_user_pending_idx
  on public.external_webhook_events (user_id, created_at desc)
  where processed_at is null;

create index if not exists external_webhook_events_provider_object_idx
  on public.external_webhook_events (provider, provider_object_id, created_at desc);
