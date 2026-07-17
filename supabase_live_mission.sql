-- CAN Rapid Aid — Live Mission: PostGIS discovery, state machine, realtime tracking
-- Run in Supabase SQL Editor AFTER supabase_pitches.sql and supabase_schema_updates.sql

-- ---------------------------------------------------------------------------
-- 1) PostGIS
-- ---------------------------------------------------------------------------
create extension if not exists postgis with schema extensions;

-- Geography point on requests (longitude FIRST in ST_MakePoint)
alter table public.requests
  add column if not exists location geography(POINT, 4326);

update public.requests r
set location = extensions.st_setsrid(
      extensions.st_makepoint(r.longitude, r.latitude),
      4326
    )::geography
where r.latitude is not null
  and r.longitude is not null
  and r.location is null;

create index if not exists idx_requests_location_gist
  on public.requests using gist (location);

-- Mission timeline audit (status transitions + helper checkpoints)
create table if not exists public.mission_events (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests (id) on delete cascade,
  event_key text not null,
  actor_id text,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists idx_mission_events_request
  on public.mission_events (request_id, created_at);

-- Live helper coordinates for active missions (requester subscribes via Realtime)
create table if not exists public.active_trips (
  request_id uuid primary key references public.requests (id) on delete cascade,
  helper_id text not null,
  requester_id text not null,
  helper_lat double precision,
  helper_lng double precision,
  updated_at timestamptz not null default now()
);

create index if not exists idx_active_trips_helper on public.active_trips (helper_id);

-- Normalize legacy request statuses → canonical state machine values
update public.requests set status = 'created' where status in ('open', 'urgent') and status not in (
  'created','pending','pitched','helper_selected','accepted','in_progress','arriving','completed'
);
update public.requests set status = 'pending' where status = 'active';
update public.requests set status = 'in_progress' where status = 'in_progress';

-- Optional: tighten status values (drop if you have custom statuses you need to keep)
alter table public.requests drop constraint if exists requests_status_check;
alter table public.requests add constraint requests_status_check check (
  status in (
    'created', 'pending', 'pitched', 'helper_selected',
    'accepted', 'in_progress', 'arriving', 'completed',
    -- legacy aliases still readable in app
    'open', 'urgent', 'active', 'closed', 'cancelled', 'canceled', 'fulfilled', 'resolved'
  )
);

comment on column public.requests.status is
  'Mission state: created→pending→pitched→helper_selected→accepted→in_progress→arriving→completed';

-- ---------------------------------------------------------------------------
-- 2) RPC: geospatial discovery (radius in meters)
-- ---------------------------------------------------------------------------
create or replace function public.get_requests_in_radius(
  user_lat double precision,
  user_lng double precision,
  radius_meters double precision
)
returns setof public.requests
language sql
stable
security invoker
as $$
  select r.*
  from public.requests r
  where r.location is not null
    and extensions.st_dwithin(
      r.location,
      extensions.st_setsrid(
        extensions.st_makepoint(user_lng, user_lat),
        4326
      )::geography,
      radius_meters
    )
    and coalesce(r.status, 'pending') in (
      'created', 'pending', 'pitched', 'open', 'urgent', 'active'
    )
  order by extensions.st_distance(
    r.location,
    extensions.st_setsrid(
      extensions.st_makepoint(user_lng, user_lat),
      4326
    )::geography
  );
$$;

grant execute on function public.get_requests_in_radius(double precision, double precision, double precision)
  to authenticated, anon;

-- Keep location in sync when lat/lng updated from Flutter
create or replace function public.sync_request_location()
returns trigger
language plpgsql
as $$
begin
  if new.latitude is not null and new.longitude is not null then
    new.location := extensions.st_setsrid(
      extensions.st_makepoint(new.longitude, new.latitude),
      4326
    )::geography;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_requests_sync_location on public.requests;
create trigger trg_requests_sync_location
  before insert or update of latitude, longitude on public.requests
  for each row execute function public.sync_request_location();

-- ---------------------------------------------------------------------------
-- 3) Realtime publication
-- ---------------------------------------------------------------------------
do $pub$
declare
  t text;
begin
  foreach t in array array['mission_events', 'active_trips'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end
$pub$;

-- ---------------------------------------------------------------------------
-- 4) Row Level Security
-- ---------------------------------------------------------------------------
alter table public.mission_events enable row level security;
alter table public.active_trips enable row level security;

drop policy if exists mission_events_read on public.mission_events;
create policy mission_events_read on public.mission_events
  for select using (
    exists (
      select 1 from public.requests req
      where req.id = mission_events.request_id
        and (
          req.user_id = auth.uid()
          or exists (
            select 1 from public.pitches p
            where p.request_id = req.id
              and p.helper_id = auth.uid()::text
              and p.status in ('awaiting_helper_ack', 'accepted')
          )
        )
    )
  );

drop policy if exists mission_events_insert on public.mission_events;
create policy mission_events_insert on public.mission_events
  for insert with check (
    actor_id = auth.uid()::text
    and exists (
      select 1 from public.requests req
      where req.id = mission_events.request_id
        and (
          req.user_id = auth.uid()
          or exists (
            select 1 from public.pitches p
            where p.request_id = req.id
              and p.helper_id = auth.uid()::text
              and p.status in ('awaiting_helper_ack', 'accepted')
          )
        )
    )
  );

drop policy if exists active_trips_select on public.active_trips;
create policy active_trips_select on public.active_trips
  for select using (
    helper_id = auth.uid()::text
    or requester_id = auth.uid()::text
  );

drop policy if exists active_trips_upsert_helper on public.active_trips;
create policy active_trips_upsert_helper on public.active_trips
  for all using (helper_id = auth.uid()::text)
  with check (helper_id = auth.uid()::text);
