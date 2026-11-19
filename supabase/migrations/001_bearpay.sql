create extension if not exists pgcrypto;
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  kyc_level smallint not null default 1 check (kyc_level in (1,2)),
  kyc_status text not null default 'not_submitted' check (kyc_status in ('not_submitted','pending','approved','rejected')),
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);
create table public.kyc_submissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  front_path text not null,
  back_path text not null,
  selfie_path text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  decision_note text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create table public.charges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  provider text not null check (provider in ('lunar','mistic')),
  amount_cents bigint not null check (amount_cents >= 200),
  fee_cents bigint not null check (fee_cents >= 0),
  status text not null default 'creating' check (status in ('creating','pending','paid','expired','cancelled','uncertain')),
  provider_id text,
  pix_code text,
  qr_image text,
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  unique(user_id,idempotency_key),
  unique(provider,provider_id)
);
create table public.withdrawals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  provider text not null check (provider in ('lunar','mistic')),
  amount_cents bigint not null check (amount_cents > 0),
  fee_cents bigint not null check (fee_cents >= 0),
  pix_key text not null,
  pix_key_type text not null,
  status text not null default 'pending_approval' check (status in ('pending_approval','processing','completed','rejected','uncertain')),
  provider_id text,
  decision_note text,
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  created_at timestamptz not null default now()
);
create table public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  subject text not null,
  message text not null,
  status text not null default 'open' check (status in ('open','answered','closed')),
  created_at timestamptz not null default now()
);
create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id),
  action text not null,
  target_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create or replace function public.is_bearpay_admin() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and is_admin=true)
$$;
create or replace function public.create_bearpay_profile() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.profiles(id,full_name,kyc_level) values (new.id,coalesce(new.raw_user_meta_data->>'full_name',''),coalesce((new.raw_user_meta_data->>'kyc_level')::smallint,1));
 return new;
end $$;
create trigger on_bearpay_user_created after insert on auth.users for each row execute function public.create_bearpay_profile();
alter table public.profiles enable row level security;
alter table public.kyc_submissions enable row level security;
alter table public.charges enable row level security;
alter table public.withdrawals enable row level security;
alter table public.support_tickets enable row level security;
alter table public.audit_events enable row level security;
create policy profiles_read on public.profiles for select to authenticated using (id=auth.uid() or public.is_bearpay_admin());
create policy kyc_read on public.kyc_submissions for select to authenticated using (user_id=auth.uid() or public.is_bearpay_admin());
create policy charges_read on public.charges for select to authenticated using (user_id=auth.uid() or public.is_bearpay_admin());
create policy withdrawals_read on public.withdrawals for select to authenticated using (user_id=auth.uid() or public.is_bearpay_admin());
create policy tickets_read on public.support_tickets for select to authenticated using (user_id=auth.uid() or public.is_bearpay_admin());
create policy audits_admin_read on public.audit_events for select to authenticated using (public.is_bearpay_admin());
insert into storage.buckets(id,name,public) values ('kyc-documents','kyc-documents',false) on conflict(id) do nothing;
create policy kyc_upload on storage.objects for insert to authenticated with check(bucket_id='kyc-documents' and (storage.foldername(name))[1]=auth.uid()::text);
create policy kyc_owner_read on storage.objects for select to authenticated using(bucket_id='kyc-documents' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_bearpay_admin()));