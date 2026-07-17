-- Rapid Aid: delete help requests older than 24 hours
-- Run in Supabase SQL Editor (after supabase_live_mission.sql + supabase_connection_fix.sql)

-- Ensure created_at exists (some projects already have it from Supabase defaults)
alter table public.requests
  add column if not exists created_at timestamptz not null default now();

create index if not exists idx_requests_created_at
  on public.requests (created_at);

-- Statuses that must NOT be auto-deleted mid-mission
create or replace function public.request_expiry_protected(status text)
returns boolean
language sql
immutable
as $$
  select coalesce(status, 'pending') in (
    'accepted',
    'in_progress',
    'arriving',
    'helper_selected',
    'awaiting_helper_ack'
  );
$$;

-- Deletes stale rows; returns number removed. Safe to call from cron or the app.
create or replace function public.purge_expired_requests()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed integer;
begin
  with gone as (
    delete from public.requests r
    where r.created_at < now() - interval '24 hours'
      and not public.request_expiry_protected(r.status)
    returning r.id
  )
  select count(*)::integer into removed from gone;
  return coalesce(removed, 0);
end;
$$;

grant execute on function public.purge_expired_requests() to authenticated;

-- Map discovery: only show requests from the last 24 hours
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
    and r.created_at >= now() - interval '24 hours'
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

-- Optional: hourly cleanup when pg_cron is enabled (Supabase paid / extension on)
do $cron$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid := (
      select jobid from cron.job where jobname = 'rapidaid-purge-requests' limit 1
    ))
    where exists (select 1 from cron.job where jobname = 'rapidaid-purge-requests');

    perform cron.schedule(
      'rapidaid-purge-requests',
      '0 * * * *',
      $$select public.purge_expired_requests();$$
    );
  end if;
exception
  when others then
    raise notice 'pg_cron schedule skipped (%). Call select public.purge_expired_requests(); manually or from the app.', sqlerrm;
end
$cron$;
