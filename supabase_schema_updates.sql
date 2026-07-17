-- RapidAid: Supabase-only extensions (run in SQL Editor after existing migrations)

-- 1) Request geo + search radius (helpers only see requests within this distance of the pin)
alter table public.requests
  add column if not exists latitude double precision;

alter table public.requests
  add column if not exists longitude double precision;

comment on column public.requests.latitude is 'Help needed here (WGS84)';
comment on column public.requests.longitude is 'Help needed here (WGS84)';
comment on column public.requests.current_radius is 'Search radius in miles from (latitude, longitude)';

-- 2) Chat (replaces Firestore)
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  participant_a text not null,
  participant_b text not null,
  last_message text,
  last_message_at timestamptz default now(),
  constraint conversations_ordered check (participant_a < participant_b)
);

create unique index if not exists idx_conversations_pair
  on public.conversations (participant_a, participant_b);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id text not null,
  body text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_chat_messages_conv on public.chat_messages (conversation_id);

alter table public.conversations enable row level security;
alter table public.chat_messages enable row level security;

drop policy if exists "conversations_all" on public.conversations;
create policy "conversations_all" on public.conversations for all using (true) with check (true);

drop policy if exists "chat_messages_all" on public.chat_messages;
create policy "chat_messages_all" on public.chat_messages for all using (true) with check (true);

-- 3) Realtime (required for .stream() on conversations / chat_messages in Flutter)
do $pub$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'conversations'
  ) then
    execute 'alter publication supabase_realtime add table public.conversations';
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_messages'
  ) then
    execute 'alter publication supabase_realtime add table public.chat_messages';
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'requests'
  ) then
    execute 'alter publication supabase_realtime add table public.requests';
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pitches'
  ) then
    execute 'alter publication supabase_realtime add table public.pitches';
  end if;
end
$pub$;

-- Self-pitch is blocked in the Flutter app. Add a DB trigger here if you want a server-side guard too.
