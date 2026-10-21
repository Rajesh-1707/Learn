alter table public.app_settings drop constraint if exists app_settings_key_check;
insert into public.app_settings(key, value)
  select 'chat_per_day_paise', value from public.app_settings where key = 'chat_price_paise'
  on conflict (key) do nothing;
delete from public.app_settings where key = 'chat_price_paise';
alter table public.app_settings add constraint app_settings_key_check
  check (key in ('audio_min_paise', 'video_min_paise', 'default_earner_percent', 'custom_earner_percent', 'chat_per_day_paise'));
insert into public.app_settings(key, value) values ('chat_per_day_paise', 500)
  on conflict (key) do nothing;

create or replace function public.owner_set_setting(p_key text, p_value integer)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_owner() then raise exception 'Owner access required'; end if;
  if p_key not in ('audio_min_paise', 'video_min_paise', 'default_earner_percent', 'custom_earner_percent', 'chat_per_day_paise') then
    raise exception 'Unknown setting';
  end if;
  if p_value < 0
    or (p_key in ('audio_min_paise', 'video_min_paise', 'chat_per_day_paise') and p_value = 0)
    or (p_key like '%earner_percent' and p_value > 100) then
    raise exception 'Invalid setting value';
  end if;
  if p_key = 'audio_min_paise' and exists (select 1 from public.profiles where audio_rate_paise is not null and audio_rate_paise < p_value) then
    raise exception 'Minimum exceeds an existing audio rate';
  end if;
  if p_key = 'video_min_paise' and exists (select 1 from public.profiles where video_rate_paise is not null and video_rate_paise < p_value) then
    raise exception 'Minimum exceeds an existing video rate';
  end if;
  insert into public.app_settings(key, value, updated_at) values (p_key, p_value, now())
    on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at;
end;
$$;
revoke all on function public.owner_set_setting(text, integer) from public;
grant execute on function public.owner_set_setting(text, integer) to authenticated;

create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_a, user_b), check (user_a < user_b)
);
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (length(btrim(body)) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index if not exists messages_chat_created_idx on public.messages(chat_id, created_at);
create table if not exists public.chat_daily_payments (
  payer_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  paid_on date not null,
  amount_paise integer not null check (amount_paise > 0),
  paid_at timestamptz not null default now(),
  primary key (payer_id, friend_id, paid_on), check (payer_id <> friend_id)
);

alter table public.chats enable row level security;
alter table public.messages enable row level security;
alter table public.chat_daily_payments enable row level security;
revoke all on public.chats, public.messages, public.chat_daily_payments from public, anon;
revoke all on public.chat_daily_payments from authenticated;
grant select on public.chats, public.messages to authenticated;
grant insert on public.messages to authenticated;

drop policy if exists "Chat members can read chats" on public.chats;
create policy "Chat members can read chats" on public.chats for select to authenticated using (
  auth.uid() in (user_a, user_b)
  and exists (select 1 from public.friendships f where f.user_a = chats.user_a and f.user_b = chats.user_b and f.status = 'accepted')
  and not public.is_blocked(case when user_a = auth.uid() then user_b else user_a end)
);
drop policy if exists "Chat members read recent messages" on public.messages;
create policy "Chat members read recent messages" on public.messages for select to authenticated using (
  created_at >= now() - interval '24 hours'
  and exists (
    select 1 from public.chats c join public.friendships f on f.user_a = c.user_a and f.user_b = c.user_b
    where c.id = messages.chat_id and auth.uid() in (c.user_a, c.user_b) and f.status = 'accepted'
      and not public.is_blocked(case when c.user_a = auth.uid() then c.user_b else c.user_a end)
        and exists (select 1 from public.chat_daily_payments d
          where d.payer_id = auth.uid()
            and d.friend_id = case when c.user_a = auth.uid() then c.user_b else c.user_a end
            and d.paid_on = current_date)
  )
);
drop policy if exists "Paid chat members can send messages" on public.messages;
create policy "Paid chat members can send messages" on public.messages for insert to authenticated with check (
  sender_id = auth.uid() and length(btrim(body)) between 1 and 4000
  and exists (
    select 1 from public.chats c join public.friendships f on f.user_a = c.user_a and f.user_b = c.user_b
    where c.id = messages.chat_id and auth.uid() in (c.user_a, c.user_b) and f.status = 'accepted'
      and not public.is_blocked(case when c.user_a = auth.uid() then c.user_b else c.user_a end)
      and exists (select 1 from public.chat_daily_payments d
        where d.payer_id = auth.uid() and d.friend_id = case when c.user_a = auth.uid() then c.user_b else c.user_a end
          and d.paid_on = current_date)
  )
);

create or replace function public.ensure_friend_chat(p_friend_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_a uuid; v_b uuid; v_chat_id uuid;
begin
  if auth.uid() is null or p_friend_id is null or p_friend_id = auth.uid() then raise exception 'Invalid friend'; end if;
  v_a := least(auth.uid(), p_friend_id); v_b := greatest(auth.uid(), p_friend_id);
  if not exists (select 1 from public.friendships where user_a = v_a and user_b = v_b and status = 'accepted')
    or public.is_blocked(p_friend_id) then raise exception 'Chats are available between friends only'; end if;
  insert into public.chats(user_a, user_b) values (v_a, v_b) on conflict (user_a, user_b) do nothing;
  select id into v_chat_id from public.chats where user_a = v_a and user_b = v_b;
  return v_chat_id;
end;
$$;

create or replace function public.chat_paid_today(p_friend_id uuid)
returns boolean language sql security definer set search_path = '' as $$
  select auth.uid() is not null and exists (select 1 from public.chat_daily_payments
    where payer_id = auth.uid() and friend_id = p_friend_id and paid_on = current_date)
$$;

create or replace function public.pay_for_chat(p_friend_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_price integer; v_balance bigint; v_a uuid; v_b uuid;
begin
  if auth.uid() is null or p_friend_id is null or p_friend_id = auth.uid() then raise exception 'Invalid friend'; end if;
  v_a := least(auth.uid(), p_friend_id); v_b := greatest(auth.uid(), p_friend_id);
  if not exists (select 1 from public.friendships where user_a = v_a and user_b = v_b and status = 'accepted')
    or public.is_blocked(p_friend_id) then raise exception 'Chats are available between friends only'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    auth.uid()::text || ':' || p_friend_id::text || ':' || current_date::text, 0));
  if exists (select 1 from public.chat_daily_payments where payer_id = auth.uid() and friend_id = p_friend_id and paid_on = current_date) then
    return 'already_paid';
  end if;
  select value into v_price from public.app_settings where key = 'chat_per_day_paise';
  if v_price is null or v_price <= 0 then raise exception 'Chat pricing is not configured'; end if;
  insert into public.wallets(user_id) values (auth.uid()) on conflict (user_id) do nothing;
  select balance_paise into v_balance from public.wallets where user_id = auth.uid() for update;
  if coalesce(v_balance, 0) < v_price then return 'insufficient_balance'; end if;
  update public.wallets set balance_paise = balance_paise - v_price, updated_at = now() where user_id = auth.uid();
  insert into public.chat_daily_payments(payer_id, friend_id, paid_on, amount_paise)
    values (auth.uid(), p_friend_id, current_date, v_price);
  insert into public.transactions(user_id, type, amount_paise, ref, note)
    values (auth.uid(), 'chat_fee', v_price, 'chat:' || p_friend_id::text || ':' || current_date::text, 'Friend chat access for the day');
  return 'paid';
end;
$$;

create or replace function public.clear_chat(p_chat_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists (select 1 from public.chats where id = p_chat_id and auth.uid() in (user_a, user_b)) then
    raise exception 'Chat not found';
  end if;
  delete from public.messages where chat_id = p_chat_id;
end;
$$;

revoke all on function public.ensure_friend_chat(uuid) from public, anon;
revoke all on function public.chat_paid_today(uuid) from public, anon;
revoke all on function public.pay_for_chat(uuid) from public, anon;
revoke all on function public.clear_chat(uuid) from public, anon;
grant execute on function public.ensure_friend_chat(uuid) to authenticated;
grant execute on function public.chat_paid_today(uuid) to authenticated;
grant execute on function public.pay_for_chat(uuid) to authenticated;
grant execute on function public.clear_chat(uuid) to authenticated;

alter table public.messages replica identity full;
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages') then
    alter publication supabase_realtime add table public.messages;
  end if;
end;
$$;

create extension if not exists pg_cron;
do $$
declare v_job_id bigint;
begin
  select jobid into v_job_id from cron.job where jobname = 'delete-expired-chat-messages';
  if v_job_id is not null then perform cron.unschedule(v_job_id); end if;
  perform cron.schedule('delete-expired-chat-messages', '0 * * * *',
    'delete from public.messages where created_at < now() - interval ''24 hours'';');
end;
$$;
