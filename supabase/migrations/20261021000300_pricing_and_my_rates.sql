create table if not exists public.app_settings (
  key text primary key,
  value integer not null,
  updated_at timestamptz not null default now(),
  constraint app_settings_key_check check (
    key in ('audio_min_paise', 'video_min_paise', 'default_earner_percent', 'custom_earner_percent', 'chat_price_paise')
  ),
  constraint app_settings_value_check check (value >= 0)
);

insert into public.app_settings(key, value) values
  ('audio_min_paise', 1000),
  ('video_min_paise', 2000),
  ('default_earner_percent', 10),
  ('custom_earner_percent', 50),
  ('chat_price_paise', 500)
on conflict (key) do nothing;

alter table public.app_settings enable row level security;
revoke all on public.app_settings from public, anon;
grant select on public.app_settings to authenticated;
drop policy if exists "Authenticated users can read app settings" on public.app_settings;
create policy "Authenticated users can read app settings"
  on public.app_settings for select to authenticated using (true);

alter table public.profiles
  add column if not exists audio_rate_paise integer,
  add column if not exists video_rate_paise integer;

create or replace function public.validate_profile_rates()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_audio_min integer;
  v_video_min integer;
begin
  select value into v_audio_min from public.app_settings where key = 'audio_min_paise';
  select value into v_video_min from public.app_settings where key = 'video_min_paise';
  if new.audio_rate_paise is not null and (v_audio_min is null or new.audio_rate_paise < v_audio_min) then
    raise exception 'Audio rate is below the current minimum';
  end if;
  if new.video_rate_paise is not null and (v_video_min is null or new.video_rate_paise < v_video_min) then
    raise exception 'Video rate is below the current minimum';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_profile_rates on public.profiles;
create trigger validate_profile_rates
before insert or update of audio_rate_paise, video_rate_paise on public.profiles
for each row execute function public.validate_profile_rates();

create or replace function public.set_my_rates(p_audio integer, p_video integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_audio_min integer;
  v_video_min integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select value into v_audio_min from public.app_settings where key = 'audio_min_paise';
  select value into v_video_min from public.app_settings where key = 'video_min_paise';
  if p_audio is not null and (v_audio_min is null or p_audio < v_audio_min) then
    raise exception 'Audio rate is below the current minimum';
  end if;
  if p_video is not null and (v_video_min is null or p_video < v_video_min) then
    raise exception 'Video rate is below the current minimum';
  end if;
  update public.profiles
    set audio_rate_paise = p_audio, video_rate_paise = p_video
    where id = auth.uid();
  if not found then raise exception 'Profile not found'; end if;
end;
$$;

create or replace function public.owner_set_setting(p_key text, p_value integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'Owner access required'; end if;
  if p_key not in ('audio_min_paise', 'video_min_paise', 'default_earner_percent', 'custom_earner_percent', 'chat_price_paise') then
    raise exception 'Unknown setting';
  end if;
  if p_value < 0
    or (p_key in ('audio_min_paise', 'video_min_paise') and p_value = 0)
    or (p_key like '%earner_percent' and p_value > 100) then
    raise exception 'Invalid setting value';
  end if;
  if p_key = 'audio_min_paise' and exists (
    select 1 from public.profiles where audio_rate_paise is not null and audio_rate_paise < p_value
  ) then raise exception 'Minimum exceeds an existing audio rate'; end if;
  if p_key = 'video_min_paise' and exists (
    select 1 from public.profiles where video_rate_paise is not null and video_rate_paise < p_value
  ) then raise exception 'Minimum exceeds an existing video rate'; end if;
  insert into public.app_settings(key, value, updated_at)
    values (p_key, p_value, now())
    on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at;
end;
$$;

revoke all on function public.set_my_rates(integer, integer) from public;
revoke all on function public.owner_set_setting(text, integer) from public;
grant execute on function public.set_my_rates(integer, integer) to authenticated;
grant execute on function public.owner_set_setting(text, integer) to authenticated;
