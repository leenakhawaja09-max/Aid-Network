-- RapidAid: mutual agreement handshake + mission feedback (run in Supabase SQL Editor)

-- 1) Pitches: allow intermediate status before locations are shared
alter table public.pitches drop constraint if exists pitches_status_check;
alter table public.pitches
  add constraint pitches_status_check
  check (status in ('pending', 'awaiting_helper_ack', 'accepted', 'declined'));

comment on column public.pitches.status is
  'pending = helper pitched; awaiting_helper_ack = requester chose this helper; accepted = helper confirmed — mission active, locations shared';

-- 2) Feedback after missions (optional columns on profiles stay; this stores each review)
create table if not exists public.mission_feedback (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests (id) on delete cascade,
  reviewer_id text not null,
  reviewee_id text not null,
  stars int not null check (stars >= 1 and stars <= 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (request_id, reviewer_id)
);

create index if not exists idx_mission_feedback_reviewee on public.mission_feedback (reviewee_id);
create index if not exists idx_mission_feedback_request on public.mission_feedback (request_id);

alter table public.mission_feedback enable row level security;

drop policy if exists "mission_feedback_all" on public.mission_feedback;
create policy "mission_feedback_all" on public.mission_feedback for all using (true) with check (true);

do $pub$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'mission_feedback'
  ) then
    execute 'alter publication supabase_realtime add table public.mission_feedback';
  end if;
end
$pub$;
