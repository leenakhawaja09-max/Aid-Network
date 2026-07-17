-- Reward accepted helper when a mission is marked completed (run in Supabase SQL Editor)

alter table public.profiles
  add column if not exists helps_count integer not null default 0;

alter table public.profiles
  add column if not exists karma_points integer not null default 0;

comment on column public.profiles.helps_count is 'Number of missions completed as helper';
comment on column public.profiles.karma_points is 'Gamification points earned helping others';

-- +1 help and +10 karma per completed mission (once per request)
create or replace function public.reward_helper_for_completed_request(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_helper text;
  v_helps integer;
  v_karma integer;
begin
  if p_request_id is null then
    return jsonb_build_object('ok', false, 'reason', 'missing_request_id');
  end if;

  if exists (
    select 1
    from public.mission_events e
    where e.request_id = p_request_id
      and e.event_key = 'helper_rewarded'
  ) then
    return jsonb_build_object('ok', true, 'already_rewarded', true);
  end if;

  select p.helper_id into v_helper
  from public.pitches p
  where p.request_id = p_request_id
    and p.status = 'accepted'
  order by p.created_at desc
  limit 1;

  if v_helper is null or trim(v_helper) = '' then
    return jsonb_build_object('ok', false, 'reason', 'no_accepted_helper');
  end if;

  update public.profiles
  set
    helps_count = coalesce(helps_count, 0) + 1,
    karma_points = coalesce(karma_points, 0) + 10
  where id::text = v_helper
  returning helps_count, karma_points into v_helps, v_karma;

  insert into public.mission_events (request_id, event_key, actor_id, note)
  values (
    p_request_id,
    'helper_rewarded',
    v_helper,
    'Helps +1, Karma +10'
  );

  return jsonb_build_object(
    'ok', true,
    'helper_id', v_helper,
    'helps_count', v_helps,
    'karma_points', v_karma
  );
end;
$$;

grant execute on function public.reward_helper_for_completed_request(uuid) to authenticated;

-- Auto-reward when a request is marked completed (works even if the app skips the RPC call).
create or replace function public.trg_reward_helper_on_request_completed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'completed'
      and (tg_op = 'INSERT' or old.status is distinct from new.status) then
    perform public.reward_helper_for_completed_request(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists requests_reward_helper_on_completed on public.requests;
create trigger requests_reward_helper_on_completed
  after insert or update of status on public.requests
  for each row
  execute function public.trg_reward_helper_on_request_completed();

-- One-time backfill (run manually after deploying this file):
-- select public.reward_helper_for_completed_request(r.id)
-- from public.requests r
-- where r.status = 'completed'
--   and not exists (
--     select 1 from public.mission_events e
--     where e.request_id = r.id and e.event_key = 'helper_rewarded'
--   );
