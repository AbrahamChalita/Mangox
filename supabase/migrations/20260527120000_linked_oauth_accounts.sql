-- Encrypted WHOOP / Strava OAuth sessions per signed-in user (restored after reinstall).

create table if not exists public.linked_oauth_accounts (
  user_id uuid not null references auth.users (id) on delete cascade,
  provider text not null check (provider in ('strava', 'whoop')),
  encrypted_payload text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, provider)
);

comment on table public.linked_oauth_accounts is
  'Per-user encrypted OAuth token blobs for Strava/WHOOP. Plaintext tokens never stored.';

alter table public.linked_oauth_accounts enable row level security;
alter table public.linked_oauth_accounts force row level security;

create policy linked_oauth_accounts_select on public.linked_oauth_accounts
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy linked_oauth_accounts_insert on public.linked_oauth_accounts
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy linked_oauth_accounts_update on public.linked_oauth_accounts
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy linked_oauth_accounts_delete on public.linked_oauth_accounts
  for delete to authenticated
  using (user_id = (select auth.uid()));

create index if not exists linked_oauth_accounts_updated_at_idx
  on public.linked_oauth_accounts (updated_at desc);
