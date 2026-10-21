alter table public.friendships rename column user_one to user_a;
alter table public.friendships rename column user_two to user_b;
alter table public.friendships
  add column status text not null default 'accepted',
  add column requested_by uuid references public.profiles(id);
update public.friendships set requested_by = user_a where requested_by is null;
alter table public.friendships alter column requested_by set not null;
alter table public.friendships add constraint friendships_status_check
  check (status in ('pending', 'accepted'));

alter table public.profiles add column if not exists last_seen_at timestamptz;

alter table public.friendships enable row level security;
revoke all on public.friendships from public, anon;
grant select on public.friendships to authenticated;
drop policy if exists "Users can read own friendships" on public.friendships;
drop policy if exists "Users can read own friendship rows" on public.friendships;
create policy "Users can read own friendship rows" on public.friendships
  for select to authenticated using (user_a = auth.uid() or user_b = auth.uid());

create or replace function public.is_blocked(p_user uuid)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1 from public.blocks b
    where (b.blocker_id = auth.uid() and b.blocked_id = p_user)
       or (b.blocker_id = p_user and b.blocked_id = auth.uid())
  )
$$;

create or replace function public.set_my_presence(p_online boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.profiles set last_seen_at = case when p_online then now() else null end
    where id = auth.uid();
end;
$$;

create or replace function public.request_friend(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_a uuid; v_b uuid; v_status text;
begin
  if auth.uid() is null or p_user is null or p_user = auth.uid() then
    raise exception 'Invalid friend';
  end if;
  if not exists (select 1 from public.profiles where id = p_user) then
    raise exception 'User not found';
  end if;
  if public.is_blocked(p_user) then raise exception 'Friend request unavailable'; end if;
  v_a := least(auth.uid(), p_user);
  v_b := greatest(auth.uid(), p_user);
  select status into v_status from public.friendships
    where user_a = v_a and user_b = v_b for update;
  if v_status is not null then return; end if;
  insert into public.friendships(user_a, user_b, status, requested_by)
    values (v_a, v_b, 'pending', auth.uid())
    on conflict (user_a, user_b) do nothing;
end;
$$;

create or replace function public.respond_friend(p_user uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_a uuid; v_b uuid;
begin
  if auth.uid() is null or p_user is null or p_user = auth.uid() then
    raise exception 'Invalid friend request';
  end if;
  v_a := least(auth.uid(), p_user);
  v_b := greatest(auth.uid(), p_user);
  if p_accept then
    update public.friendships set status = 'accepted'
      where user_a = v_a and user_b = v_b and status = 'pending'
        and requested_by = p_user;
  else
    delete from public.friendships
      where user_a = v_a and user_b = v_b and status = 'pending'
        and requested_by = p_user;
  end if;
  if not found then raise exception 'Friend request not found'; end if;
end;
$$;

create or replace function public.list_friends()
returns table(
  user_id uuid,
  full_name text,
  avatar_url text,
  audio_rate_paise integer,
  video_rate_paise integer,
  online boolean
)
language sql
security definer
set search_path = ''
as $$
  select p.id, p.full_name, p.avatar_url, p.audio_rate_paise, p.video_rate_paise,
    coalesce(p.last_seen_at > now() - interval '75 seconds', false)
  from public.friendships f
  join public.profiles p on p.id = case when f.user_a = auth.uid() then f.user_b else f.user_a end
  where (f.user_a = auth.uid() or f.user_b = auth.uid())
    and f.status = 'accepted'
    and not public.is_blocked(p.id)
  order by p.full_name
$$;

create or replace function public.list_friend_requests()
returns table(request_id uuid, user_id uuid, full_name text, avatar_url text, created_at timestamptz)
language sql
security definer
set search_path = ''
as $$
  select f.requested_by, p.id, p.full_name, p.avatar_url, f.created_at
  from public.friendships f
  join public.profiles p on p.id = f.requested_by
  where (f.user_a = auth.uid() or f.user_b = auth.uid())
    and f.status = 'pending' and f.requested_by <> auth.uid()
  order by f.created_at desc
$$;

create or replace function public.list_my_friends()
returns table(user_id uuid, full_name text, avatar_url text, audio_rate_paise integer, video_rate_paise integer)
language sql
security definer
set search_path = ''
as $$
  select f.user_id, f.full_name, f.avatar_url, f.audio_rate_paise, f.video_rate_paise
  from public.list_friends() f
$$;

create or replace function public.start_friend_call(p_friend_id uuid, p_media_type text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_call_id uuid;
begin
  if p_media_type not in ('audio', 'video') then raise exception 'Invalid call type'; end if;
  if auth.uid() is null or not exists (
    select 1 from public.friendships
      where user_a = least(auth.uid(), p_friend_id)
        and user_b = greatest(auth.uid(), p_friend_id)
        and status = 'accepted'
  ) then raise exception 'Friendship required'; end if;
  if public.is_blocked(p_friend_id) then raise exception 'Not available'; end if;
  if not exists (
    select 1 from public.profiles
    where id = p_friend_id and last_seen_at > now() - interval '75 seconds'
  ) then raise exception 'Not available'; end if;
  insert into public.calls(caller_id, receiver_id, status, media, media_type)
    values (auth.uid(), p_friend_id, 'matched', p_media_type, p_media_type)
    returning id into v_call_id;
  return v_call_id;
end;
$$;

create or replace function public.pending_friend_call()
returns table(call_id uuid, media_type text)
language sql
security definer
set search_path = ''
as $$
  select c.id, c.media
  from public.calls c
  where c.receiver_id = auth.uid() and c.status = 'matched'
    and c.created_at > now() - interval '90 seconds'
  order by c.created_at desc
  limit 1
$$;

revoke all on function public.is_blocked(uuid) from public, anon;
revoke all on function public.set_my_presence(boolean) from public, anon;
revoke all on function public.request_friend(uuid) from public, anon;
revoke all on function public.respond_friend(uuid, boolean) from public, anon;
revoke all on function public.list_friends() from public, anon;
revoke all on function public.list_friend_requests() from public, anon;
revoke all on function public.list_my_friends() from public, anon;
revoke all on function public.start_friend_call(uuid, text) from public, anon;
revoke all on function public.pending_friend_call() from public, anon;
revoke all on function public.send_friend_request(uuid) from public, anon, authenticated;
revoke all on function public.respond_friend_request(uuid, boolean) from public, anon, authenticated;
grant execute on function public.is_blocked(uuid) to authenticated;
grant execute on function public.set_my_presence(boolean) to authenticated;
grant execute on function public.request_friend(uuid) to authenticated;
grant execute on function public.respond_friend(uuid, boolean) to authenticated;
grant execute on function public.list_friends() to authenticated;
grant execute on function public.list_friend_requests() to authenticated;
grant execute on function public.list_my_friends() to authenticated;
grant execute on function public.start_friend_call(uuid, text) to authenticated;
grant execute on function public.pending_friend_call() to authenticated;
