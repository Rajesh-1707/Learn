alter table public.app_settings drop constraint if exists app_settings_key_check;
alter table public.app_settings add constraint app_settings_key_check
  check (key in ('audio_min_paise', 'video_min_paise', 'default_earner_percent', 'custom_earner_percent', 'chat_price_paise'));
insert into public.app_settings(key, value) values ('chat_price_paise', 500)
on conflict (key) do nothing;

create or replace function public.owner_set_setting(p_key text, p_value integer)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_owner() then raise exception 'Owner access required'; end if;
  if p_key not in ('audio_min_paise', 'video_min_paise', 'default_earner_percent', 'custom_earner_percent', 'chat_price_paise') then
    raise exception 'Unknown setting';
  end if;
  if p_value < 0
    or (p_key in ('audio_min_paise', 'video_min_paise', 'chat_price_paise') and p_value = 0)
    or (p_key like '%earner_percent' and p_value > 100) then
    raise exception 'Invalid setting value';
  end if;
  if p_key = 'audio_min_paise' and exists (select 1 from public.profiles where audio_rate_paise is not null and audio_rate_paise < p_value) then
    raise exception 'Minimum exceeds an existing audio rate';
  end if;
  if p_key = 'video_min_paise' and exists (select 1 from public.profiles where video_rate_paise is not null and video_rate_paise < p_value) then
    raise exception 'Minimum exceeds an existing video rate';
  end if;
  insert into public.app_settings(key, value, updated_at)
    values (p_key, p_value, now())
    on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at;
end;
$$;
revoke all on function public.owner_set_setting(text, integer) from public;
grant execute on function public.owner_set_setting(text, integer) to authenticated;

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  check (sender_id <> recipient_id)
);
create index if not exists friend_requests_recipient_idx
  on public.friend_requests(recipient_id, status, created_at desc);
create unique index if not exists friend_requests_pending_unique
  on public.friend_requests(sender_id, recipient_id) where status = 'pending';

create table if not exists public.friendships (
  user_one uuid not null references public.profiles(id) on delete cascade,
  user_two uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_one, user_two),
  check (user_one < user_two)
);
alter table public.calls add column if not exists media_type text not null default 'audio'
  check (media_type in ('audio', 'video'));
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
revoke all on public.friend_requests, public.friendships from public, anon;
grant select on public.friend_requests, public.friendships to authenticated;
drop policy if exists "Users can read own friend requests" on public.friend_requests;
create policy "Users can read own friend requests" on public.friend_requests
  for select to authenticated using (sender_id = auth.uid() or recipient_id = auth.uid());
drop policy if exists "Users can read own friendships" on public.friendships;
create policy "Users can read own friendships" on public.friendships
  for select to authenticated using (user_one = auth.uid() or user_two = auth.uid());

create or replace function public.send_friend_request(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or p_user_id = auth.uid() then raise exception 'Invalid friend'; end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then raise exception 'User not found'; end if;
  if exists (select 1 from public.friendships where user_one = least(auth.uid(), p_user_id) and user_two = greatest(auth.uid(), p_user_id)) then return; end if;
  if exists (select 1 from public.friend_requests where sender_id = p_user_id and recipient_id = auth.uid() and status = 'pending') then
    insert into public.friendships(user_one, user_two) values (least(auth.uid(), p_user_id), greatest(auth.uid(), p_user_id)) on conflict do nothing;
    update public.friend_requests set status = 'accepted' where sender_id = p_user_id and recipient_id = auth.uid() and status = 'pending';
    return;
  end if;
  insert into public.friend_requests(sender_id, recipient_id) values (auth.uid(), p_user_id) on conflict do nothing;
end;
$$;

create or replace function public.respond_friend_request(p_request_id uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v_sender uuid; v_recipient uuid;
begin
  update public.friend_requests set status = case when p_accept then 'accepted' else 'declined' end
    where id = p_request_id and recipient_id = auth.uid() and status = 'pending'
    returning sender_id, recipient_id into v_sender, v_recipient;
  if v_sender is null then raise exception 'Request not found'; end if;
  if p_accept then
    insert into public.friendships(user_one, user_two)
      values (least(v_sender, v_recipient), greatest(v_sender, v_recipient)) on conflict do nothing;
  end if;
end;
$$;

create or replace function public.list_my_friends()
returns table(user_id uuid, full_name text, avatar_url text, audio_rate_paise integer, video_rate_paise integer)
language sql security definer set search_path = '' as $$
  select p.id, p.full_name, p.avatar_url, p.audio_rate_paise, p.video_rate_paise
  from public.friendships f join public.profiles p on p.id = case when f.user_one = auth.uid() then f.user_two else f.user_one end
  where f.user_one = auth.uid() or f.user_two = auth.uid()
  order by p.full_name;
$$;

create or replace function public.search_friend_candidates(p_query text)
returns table(user_id uuid, full_name text, avatar_url text, audio_rate_paise integer, video_rate_paise integer)
language sql security definer set search_path = '' as $$
  select p.id, p.full_name, p.avatar_url, p.audio_rate_paise, p.video_rate_paise
  from public.profiles p
  where p.id <> auth.uid()
    and (p.full_name ilike '%' || btrim(p_query) || '%' or p.id::text ilike btrim(p_query) || '%')
  order by p.full_name
  limit 20;
$$;

create or replace function public.list_friend_requests()
returns table(request_id uuid, user_id uuid, full_name text, avatar_url text, created_at timestamptz)
language sql security definer set search_path = '' as $$
  select f.id, p.id, p.full_name, p.avatar_url, f.created_at
  from public.friend_requests f join public.profiles p on p.id = f.sender_id
  where f.recipient_id = auth.uid() and f.status = 'pending'
  order by f.created_at desc;
$$;

create or replace function public.start_friend_call(p_friend_id uuid, p_media_type text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_call_id uuid;
begin
  if p_media_type not in ('audio', 'video') then raise exception 'Invalid call type'; end if;
  if auth.uid() is null or not exists (
    select 1 from public.friendships where user_one = least(auth.uid(), p_friend_id) and user_two = greatest(auth.uid(), p_friend_id)
  ) then raise exception 'Friendship required'; end if;
  insert into public.calls(caller_id, receiver_id, status, media_type)
    values (auth.uid(), p_friend_id, 'matched', p_media_type) returning id into v_call_id;
  return v_call_id;
end;
$$;

create or replace function public.pending_friend_call()
returns table(call_id uuid, media_type text)
language sql security definer set search_path = '' as $$
  select c.id, c.media_type
  from public.calls c
  where c.receiver_id = auth.uid() and c.status = 'matched'
    and c.created_at > now() - interval '90 seconds'
  order by c.created_at desc
  limit 1;
$$;

create or replace function public.owner_set_gender_verified(p_user_id uuid, p_verified boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_owner() then raise exception 'Owner access required'; end if;
  update public.profiles set verified_gender = p_verified where id = p_user_id;
  if not found then raise exception 'User not found'; end if;
end;
$$;

create or replace function public.owner_today_collected_paise()
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_total bigint;
begin
  if not public.is_owner() then raise exception 'Owner access required'; end if;
  select coalesce(sum(amount_paise), 0)::bigint into v_total
    from public.transactions
    where type in ('topup', 'call_fee', 'chat_fee')
      and created_at >= date_trunc('day', now());
  return v_total;
end;
$$;

revoke all on function public.send_friend_request(uuid) from public;
revoke all on function public.respond_friend_request(uuid, boolean) from public;
revoke all on function public.list_my_friends() from public;
revoke all on function public.search_friend_candidates(text) from public;
revoke all on function public.list_friend_requests() from public;
revoke all on function public.start_friend_call(uuid, text) from public;
revoke all on function public.pending_friend_call() from public;
revoke all on function public.owner_set_gender_verified(uuid, boolean) from public;
revoke all on function public.owner_today_collected_paise() from public;
grant execute on function public.send_friend_request(uuid) to authenticated;
grant execute on function public.respond_friend_request(uuid, boolean) to authenticated;
grant execute on function public.list_my_friends() to authenticated;
grant execute on function public.search_friend_candidates(text) to authenticated;
grant execute on function public.list_friend_requests() to authenticated;
grant execute on function public.start_friend_call(uuid, text) to authenticated;
grant execute on function public.pending_friend_call() to authenticated;
grant execute on function public.owner_set_gender_verified(uuid, boolean) to authenticated;
grant execute on function public.owner_today_collected_paise() to authenticated;
