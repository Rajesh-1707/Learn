alter table public.profiles
  add column if not exists dob date,
  add column if not exists city text,
  add column if not exists state text;

create or replace function public.owner_list_users(
  p_search text,
  p_limit int,
  p_offset int
)
returns table (
  id uuid,
  full_name text,
  gender text,
  city text,
  state text,
  role text,
  created_at timestamptz,
  balance_paise bigint,
  earnings_paise bigint,
  verified_gender boolean
)
language sql
security definer
set search_path = ''
as $$
  select
    p.id,
    p.full_name,
    p.gender,
    p.city,
    p.state,
    p.role,
    p.created_at,
    coalesce(w.balance_paise, 0)::bigint,
    coalesce(w.earnings_paise, 0)::bigint,
    p.verified_gender
  from public.profiles as p
  left join public.wallets as w on w.user_id = p.id
  where public.is_owner()
    and (
      nullif(btrim(p_search), '') is null
      or p.full_name ilike '%' || btrim(p_search) || '%'
      or p.city ilike '%' || btrim(p_search) || '%'
      or p.state ilike '%' || btrim(p_search) || '%'
      or p.gender ilike '%' || btrim(p_search) || '%'
    )
  order by p.created_at desc, p.id
  limit greatest(1, least(coalesce(p_limit, 30), 100))
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on function public.owner_list_users(text, int, int) from public;
grant execute on function public.owner_list_users(text, int, int) to authenticated;
