-- RapidAid: pitches handshake + profile coordinates for maps
-- Run in Supabase SQL Editor (adjust RLS for production).

-- 1) Pitches table
create table if not exists public.pitches (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests (id) on delete cascade,
  helper_id text not null,
  pitch_message text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  constraint pitches_status_check check (status in ('pending', 'awaiting_helper_ack', 'accepted', 'declined'))
);

create index if not exists idx_pitches_request_id on public.pitches (request_id);
create index if not exists idx_pitches_helper_id on public.pitches (helper_id);
create index if not exists idx_pitches_status on public.pitches (status);

-- 2) Profile coordinates (used for live map markers)
alter table public.profiles
  add column if not exists latitude double precision;

alter table public.profiles
  add column if not exists longitude double precision;

comment on column public.profiles.latitude is 'Last known latitude for map / ETA';
comment on column public.profiles.longitude is 'Last known longitude for map / ETA';

-- 3) Dev-friendly RLS (replace with auth.uid()-based policies before production)
alter table public.pitches enable row level security;

drop policy if exists "pitches_select_all" on public.pitches;
create policy "pitches_select_all" on public.pitches
  for select using (true);

drop policy if exists "pitches_insert_all" on public.pitches;
create policy "pitches_insert_all" on public.pitches
  for insert with check (true);

drop policy if exists "pitches_update_all" on public.pitches;
create policy "pitches_update_all" on public.pitches
  for update using (true);

-- Ensure requests can move to in-progress (no schema change if status is text)
comment on column public.requests.status is 'e.g. open, urgent, Active, in-progress, completed';
