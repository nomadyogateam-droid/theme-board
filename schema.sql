-- Nomad Yoga Theme Board: run this whole file once in Supabase > SQL Editor.
-- Before running, replace nomadyogateam@gmail.com (it appears once, in admin_delete_request) with your owner email.

create extension if not exists pgcrypto;

create table if not exists public.requests (
  id uuid primary key default gen_random_uuid(),
  theme text not null check (char_length(theme) between 1 and 60),
  device_id text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.votes (
  request_id uuid not null references public.requests(id) on delete cascade,
  device_id text not null,
  primary key (request_id, device_id)
);

-- Lock the tables: nobody can touch them directly. All access goes through the functions below.
alter table public.requests enable row level security;
alter table public.votes enable row level security;

-- Public read-only view with vote counts (no device ids exposed).
create or replace view public.request_board as
  select r.id, r.theme, r.created_at, count(v.device_id)::int as votes
  from public.requests r
  left join public.votes v on v.request_id = r.id
  group by r.id;

grant select on public.request_board to anon, authenticated;

create or replace function public.add_request(p_theme text, p_device text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare new_id uuid;
begin
  p_theme := btrim(p_theme);
  if p_theme is null or char_length(p_theme) < 1 or char_length(p_theme) > 60 then
    raise exception 'invalid theme';
  end if;
  if p_device is null or char_length(p_device) < 8 then
    raise exception 'invalid device';
  end if;
  insert into requests (theme, device_id) values (p_theme, p_device) returning id into new_id;
  insert into votes (request_id, device_id) values (new_id, p_device);
  return new_id;
end $$;

-- Returns true if the vote is now ON, false if it was removed.
create or replace function public.toggle_vote(p_request uuid, p_device text)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_device is null or char_length(p_device) < 8 then
    raise exception 'invalid device';
  end if;
  if exists (select 1 from votes where request_id = p_request and device_id = p_device) then
    delete from votes where request_id = p_request and device_id = p_device;
    return false;
  end if;
  insert into votes (request_id, device_id) values (p_request, p_device);
  return true;
end $$;

create or replace function public.my_votes(p_device text)
returns setof uuid
language sql security definer set search_path = public as $$
  select request_id from votes where device_id = p_device;
$$;

create or replace function public.delete_own_request(p_request uuid, p_device text)
returns void
language sql security definer set search_path = public as $$
  delete from requests where id = p_request and device_id = p_device;
$$;

-- Owner only: must be signed in as this email.
create or replace function public.admin_delete_request(p_request uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.jwt() ->> 'email', '') <> 'nomadyogateam@gmail.com' then
    raise exception 'not allowed';
  end if;
  delete from requests where id = p_request;
end $$;

revoke all on function public.add_request(text, text) from public;
revoke all on function public.toggle_vote(uuid, text) from public;
revoke all on function public.my_votes(text) from public;
revoke all on function public.delete_own_request(uuid, text) from public;
revoke all on function public.admin_delete_request(uuid) from public;

grant execute on function public.add_request(text, text) to anon, authenticated;
grant execute on function public.toggle_vote(uuid, text) to anon, authenticated;
grant execute on function public.my_votes(text) to anon, authenticated;
grant execute on function public.delete_own_request(uuid, text) to anon, authenticated;
grant execute on function public.admin_delete_request(uuid) to authenticated;
