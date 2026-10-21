alter table public.wallets
  add column if not exists pending_paise bigint not null default 0;
alter table public.calls
  add column if not exists ended_at timestamptz;

create table if not exists public.call_billing_sessions (
  call_id uuid primary key references public.calls(id) on delete cascade,
  started_at timestamptz not null default now()
);

create table if not exists public.call_minute_ledger (
  call_id uuid not null references public.calls(id) on delete cascade,
  minute_number integer not null check (minute_number > 0),
  payer_id uuid not null references public.profiles(id),
  receiver_id uuid not null references public.profiles(id),
  media_type text not null check (media_type in ('audio', 'video')),
  rate_paise integer not null check (rate_paise > 0),
  earner_paise integer not null check (earner_paise >= 0),
  created_at timestamptz not null default now(),
  primary key (call_id, minute_number)
);
alter table public.call_minute_ledger enable row level security;
revoke all on public.call_minute_ledger from public, anon, authenticated;

create or replace function public.bill_minute(p_call_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_payer uuid;
  v_receiver uuid;
  v_media_type text;
  v_call_status text;
  v_started_at timestamptz;
  v_minute integer;
  v_rate integer;
  v_minimum integer;
  v_earner_percent integer;
  v_earner_amount bigint;
  v_balance bigint;
  v_inserted integer;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select caller_id, receiver_id, media_type, status
    into v_payer, v_receiver, v_media_type, v_call_status
    from public.calls where id = p_call_id for update;
  if not found then raise exception 'Call not found'; end if;
  if v_user <> v_payer and v_user <> v_receiver then raise exception 'Not a call participant'; end if;
  if v_call_status in ('ended', 'cancelled', 'completed', 'declined', 'failed') then
    return 'ended';
  end if;

  insert into public.call_billing_sessions(call_id) values (p_call_id)
    on conflict (call_id) do nothing;
  select started_at into v_started_at
    from public.call_billing_sessions where call_id = p_call_id for update;
  v_minute := greatest(1, floor(extract(epoch from (now() - v_started_at)) / 60)::integer + 1);

  if v_media_type = 'video' then
    select value into v_minimum from public.app_settings where key = 'video_min_paise';
    select coalesce(p.video_rate_paise, v_minimum) into v_rate
      from public.profiles p where p.id = v_receiver;
  else
    select value into v_minimum from public.app_settings where key = 'audio_min_paise';
    select coalesce(p.audio_rate_paise, v_minimum) into v_rate
      from public.profiles p where p.id = v_receiver;
  end if;
  if v_rate is null or v_minimum is null or v_rate < v_minimum then
    raise exception 'Call pricing is not configured';
  end if;
  if v_rate > v_minimum then
    select value into v_earner_percent from public.app_settings where key = 'custom_earner_percent';
  else
    select value into v_earner_percent from public.app_settings where key = 'default_earner_percent';
  end if;
  v_earner_amount := (v_rate::bigint * coalesce(v_earner_percent, 0)) / 100;

  insert into public.wallets(user_id) values (v_payer), (v_receiver)
    on conflict (user_id) do nothing;

  -- Serialize billing for this call. The primary key makes retries harmless.
  insert into public.call_minute_ledger
    (call_id, minute_number, payer_id, receiver_id, media_type, rate_paise, earner_paise)
    values (p_call_id, v_minute, v_payer, v_receiver, v_media_type, v_rate, v_earner_amount)
    on conflict (call_id, minute_number) do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    select balance_paise into v_balance from public.wallets where user_id = v_payer;
    return case when coalesce(v_balance, 0) < v_rate then 'low_balance' else 'already_billed' end;
  end if;

  select balance_paise into v_balance
    from public.wallets where user_id = v_payer for update;
  if coalesce(v_balance, 0) < v_rate then
    delete from public.call_minute_ledger where call_id = p_call_id and minute_number = v_minute;
    update public.calls set status = 'ended', ended_at = now() where id = p_call_id;
    return 'low_balance';
  end if;

  update public.wallets
    set balance_paise = balance_paise - v_rate, updated_at = now()
    where user_id = v_payer;
  update public.wallets
    set pending_paise = pending_paise + v_earner_amount, updated_at = now()
    where user_id = v_receiver;
  insert into public.transactions(user_id, type, amount_paise, ref, note)
    values (v_payer, 'call_fee', v_rate, p_call_id::text || ':' || v_minute::text,
      'Call minute ' || v_minute::text);

  select balance_paise into v_balance from public.wallets where user_id = v_payer;
  if v_balance < v_rate then
    update public.calls set status = 'ended', ended_at = now() where id = p_call_id;
    return 'low_balance';
  end if;
  return 'billed';
end;
$$;
revoke all on function public.bill_minute(uuid) from public, anon;
grant execute on function public.bill_minute(uuid) to authenticated;

create or replace function public.release_pending_earnings()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wallet record;
  v_total bigint := 0;
begin
  for v_wallet in
    select user_id, pending_paise from public.wallets
    where pending_paise > 0 for update skip locked
  loop
    update public.wallets
      set earnings_paise = earnings_paise + v_wallet.pending_paise,
          pending_paise = 0,
          updated_at = now()
      where user_id = v_wallet.user_id;
    insert into public.transactions(user_id, type, amount_paise, ref, note)
      values (v_wallet.user_id, 'call_earning', v_wallet.pending_paise,
        'pending-release:' || current_date::text, 'Daily call earnings release');
    v_total := v_total + v_wallet.pending_paise;
  end loop;
  return v_total;
end;
$$;
revoke all on function public.release_pending_earnings() from public, anon, authenticated;
grant execute on function public.release_pending_earnings() to service_role;

-- Supabase projects provide pg_cron. Scheduling the same named job is
-- idempotent when this migration is reapplied in a development database.
create extension if not exists pg_cron;
do $$
declare v_job_id bigint;
begin
  select jobid into v_job_id from cron.job where jobname = 'release-pending-earnings-daily';
  if v_job_id is not null then perform cron.unschedule(v_job_id); end if;
  perform cron.schedule(
    'release-pending-earnings-daily',
    '5 0 * * *',
    'select public.release_pending_earnings();'
  );
end;
$$;
