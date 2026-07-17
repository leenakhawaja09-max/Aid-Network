-- Rapid Aid: fix helper ↔ requester "connection failed" (RLS + discovery RPC)
-- Run in Supabase SQL Editor AFTER supabase_live_mission.sql
-- Safe to re-run (drops/recreates policies).

-- ---------------------------------------------------------------------------
-- 1) Discovery RPC runs as owner so helpers see nearby open requests
--    even when RLS limits direct SELECT on rows they do not own.
-- ---------------------------------------------------------------------------
create or replace function public.get_requests_in_radius(
  user_lat double precision,
  user_lng double precision,
  radius_meters double precision
)
returns setof public.requests
language sql
stable
security definer
set search_path = public, extensions
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

-- ---------------------------------------------------------------------------
-- 2) requests: helpers must read open requests; assigned helper must update status
-- ---------------------------------------------------------------------------
alter table public.requests enable row level security;

drop policy if exists requests_select_authenticated on public.requests;
create policy requests_select_authenticated on public.requests
  for select to authenticated
  using (true);

drop policy if exists requests_insert_own on public.requests;
create policy requests_insert_own on public.requests
  for insert to authenticated
  with check (user_id::text = auth.uid()::text);

drop policy if exists requests_update_owner on public.requests;
create policy requests_update_owner on public.requests
  for update to authenticated
  using (user_id::text = auth.uid()::text)
  with check (user_id::text = auth.uid()::text);

drop policy if exists requests_update_assigned_helper on public.requests;
create policy requests_update_assigned_helper on public.requests
  for update to authenticated
  using (
    exists (
      select 1 from public.pitches p
      where p.request_id = requests.id
        and p.helper_id = auth.uid()::text
        and p.status in ('awaiting_helper_ack', 'accepted')
    )
  )
  with check (true);

-- ---------------------------------------------------------------------------
-- 3) profiles: read for matching; update own coords for live map
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;

drop policy if exists profiles_select_authenticated on public.profiles;
create policy profiles_select_authenticated on public.profiles
  for select to authenticated
  using (true);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id::text = auth.uid()::text)
  with check (id::text = auth.uid()::text);

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert to authenticated
  with check (id::text = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- 4) mission_events / active_trips: fix uuid/text comparisons
-- ---------------------------------------------------------------------------
drop policy if exists mission_events_read on public.mission_events;
create policy mission_events_read on public.mission_events
  for select using (
    exists (
      select 1 from public.requests req
      where req.id = mission_events.request_id
        and (
          req.user_id::text = auth.uid()::text
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
          req.user_id::text = auth.uid()::text
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

-- ---------------------------------------------------------------------------
-- 5) Realtime publication (required for .stream() — fixes websocket errors)
-- ---------------------------------------------------------------------------
do $pub$
declare
  t text;
begin
  foreach t in array array[
    'requests', 'pitches', 'profiles', 'conversations', 'chat_messages',
    'mission_events', 'active_trips'
  ] loop
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
