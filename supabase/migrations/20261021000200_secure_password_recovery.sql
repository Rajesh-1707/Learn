alter table public.profiles
  add column if not exists recovery_code_hash text,
  add column if not exists password_reset_at timestamptz,
  add column if not exists reset_locked_until timestamptz;

create table if not exists public.reset_attempts (
  id uuid primary key default gen_random_uuid(),
  email_key text not null,
  ip_key text not null,
  attempted_at timestamptz not null default now(),
  succeeded boolean
);

create index if not exists reset_attempts_email_time_idx
  on public.reset_attempts (email_key, attempted_at desc);
create index if not exists reset_attempts_ip_time_idx
  on public.reset_attempts (ip_key, attempted_at desc);

alter table public.reset_attempts enable row level security;
revoke all on public.reset_attempts from public, anon, authenticated;
grant all on public.reset_attempts to service_role;

create or replace function public.begin_reset_attempt(p_email_key text, p_ip_key text)
returns table (attempt_id uuid, allowed boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email_lock bigint;
  v_ip_lock bigint;
  v_count bigint;
  v_attempt_id uuid;
begin
  v_email_lock := pg_catalog.hashtextextended(p_email_key, 0);
  v_ip_lock := pg_catalog.hashtextextended(p_ip_key, 0);
  perform pg_catalog.pg_advisory_xact_lock(v_email_lock);
  perform pg_catalog.pg_advisory_xact_lock(v_ip_lock);

  select count(*) into v_count
    from public.reset_attempts
    where email_key = p_email_key and attempted_at > now() - interval '1 hour';
  if v_count >= 5 then
    return query select null::uuid, false;
    return;
  end if;

  select count(*) into v_count
    from public.reset_attempts
    where ip_key = p_ip_key and attempted_at > now() - interval '1 hour';
  if v_count >= 5 then
    return query select null::uuid, false;
    return;
  end if;

  insert into public.reset_attempts(email_key, ip_key)
    values (p_email_key, p_ip_key) returning id into v_attempt_id;
  return query select v_attempt_id, true;
end;
$$;

create or replace function public.finish_reset_attempt(p_attempt_id uuid, p_succeeded boolean, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email_key text;
  v_failures bigint;
begin
  update public.reset_attempts
    set succeeded = p_succeeded
    where id = p_attempt_id and succeeded is null
    returning email_key into v_email_key;
  if v_email_key is null then return; end if;

  if not p_succeeded then
    select count(*) into v_failures
      from public.reset_attempts
      where email_key = v_email_key
        and succeeded = false
        and attempted_at > now() - interval '1 hour';
    if v_failures >= 5 then
      if p_user_id is not null then
        update public.profiles set reset_locked_until = now() + interval '1 hour' where id = p_user_id;
      end if;
    end if;
  end if;
end;
$$;

create or replace function public.lookup_reset_profile(p_email text)
returns table (user_id uuid, dob date, recovery_code_hash text, reset_locked_until timestamptz)
language sql
security definer
set search_path = ''
as $$
  select p.id, p.dob, p.recovery_code_hash, p.reset_locked_until
  from public.profiles p
  join auth.users u on u.id = p.id
  where lower(u.email) = lower(p_email)
  limit 1;
$$;

revoke all on function public.begin_reset_attempt(text, text) from public, anon, authenticated;
revoke all on function public.finish_reset_attempt(uuid, boolean, uuid) from public, anon, authenticated;
revoke all on function public.lookup_reset_profile(text) from public, anon, authenticated;
grant execute on function public.begin_reset_attempt(text, text) to service_role;
grant execute on function public.finish_reset_attempt(uuid, boolean, uuid) to service_role;
grant execute on function public.lookup_reset_profile(text) to service_role;

create or replace function public.block_withdrawal_after_password_reset()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reset_at timestamptz;
begin
  if new.type = 'payout' then
    select password_reset_at into v_reset_at
      from public.profiles where id = new.user_id;
    if v_reset_at > now() - interval '24 hours' then
      raise exception 'Withdrawals are temporarily unavailable after a password reset';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists block_withdrawal_after_password_reset on public.transactions;
create trigger block_withdrawal_after_password_reset
before insert on public.transactions
for each row execute function public.block_withdrawal_after_password_reset();
