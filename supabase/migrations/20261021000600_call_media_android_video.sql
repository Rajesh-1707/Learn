alter table public.calls
  add column if not exists media text not null default 'audio';

update public.calls
set media = media_type
where media_type in ('audio', 'video') and media <> media_type;

alter table public.calls drop constraint if exists calls_media_check;
alter table public.calls add constraint calls_media_check
  check (media in ('audio', 'video'));

create or replace function public.sync_call_media_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.media is distinct from 'audio' then
      new.media_type := new.media;
    else
      new.media := coalesce(new.media_type, 'audio');
    end if;
  elsif new.media is distinct from old.media then
    new.media_type := new.media;
  elsif new.media_type is distinct from old.media_type then
    new.media := new.media_type;
  end if;
  return new;
end;
$$;
drop trigger if exists sync_call_media_columns on public.calls;
create trigger sync_call_media_columns
before insert or update of media, media_type on public.calls
for each row execute function public.sync_call_media_columns();

create table if not exists public.call_media_selections (
  call_id uuid primary key references public.calls(id) on delete cascade,
  media text not null check (media in ('audio', 'video')),
  selected_at timestamptz not null default now()
);
alter table public.call_media_selections enable row level security;
revoke all on public.call_media_selections from public, anon, authenticated;

create or replace function public.choose_call_media(p_call_id uuid, p_media text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_selected text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_media not in ('audio', 'video') then raise exception 'Invalid call media'; end if;
  if not exists (
    select 1 from public.calls
    where id = p_call_id and auth.uid() in (caller_id, receiver_id)
      and status not in ('ended', 'cancelled', 'completed', 'declined', 'failed')
  ) then raise exception 'Call is unavailable'; end if;

  insert into public.call_media_selections(call_id, media)
    values (p_call_id, p_media) on conflict (call_id) do nothing;
  select media into v_selected from public.call_media_selections where call_id = p_call_id;
  update public.calls set media = v_selected where id = p_call_id;
  return v_selected;
end;
$$;

create or replace function public.get_call_media(p_call_id uuid)
returns text
language sql
security definer
set search_path = ''
as $$
  select c.media from public.calls c
  where c.id = p_call_id and auth.uid() in (c.caller_id, c.receiver_id)
$$;

create or replace function public.start_friend_call(p_friend_id uuid, p_media_type text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_call_id uuid;
begin
  if p_media_type not in ('audio', 'video') then raise exception 'Invalid call type'; end if;
  if auth.uid() is null or not exists (
    select 1 from public.friendships where user_one = least(auth.uid(), p_friend_id) and user_two = greatest(auth.uid(), p_friend_id)
  ) then raise exception 'Friendship required'; end if;
  insert into public.calls(caller_id, receiver_id, status, media, media_type)
    values (auth.uid(), p_friend_id, 'matched', p_media_type, p_media_type)
    returning id into v_call_id;
  return v_call_id;
end;
$$;

create or replace function public.pending_friend_call()
returns table(call_id uuid, media_type text)
language sql security definer set search_path = '' as $$
  select c.id, c.media
  from public.calls c
  where c.receiver_id = auth.uid() and c.status = 'matched'
    and c.created_at > now() - interval '90 seconds'
  order by c.created_at desc
  limit 1;
$$;

revoke all on function public.choose_call_media(uuid, text) from public, anon;
revoke all on function public.get_call_media(uuid) from public, anon;
revoke all on function public.start_friend_call(uuid, text) from public;
revoke all on function public.pending_friend_call() from public;
grant execute on function public.choose_call_media(uuid, text) to authenticated;
grant execute on function public.get_call_media(uuid) to authenticated;
grant execute on function public.start_friend_call(uuid, text) to authenticated;
grant execute on function public.pending_friend_call() to authenticated;
