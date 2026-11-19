-- BearPay · Execute no SQL Editor do Supabase em um projeto novo.
create extension if not exists pgcrypto;

create type public.user_role as enum ('merchant','admin','support');
create type public.kyc_tier as enum ('kyc1','kyc2');
create type public.kyc_state as enum ('not_submitted','under_review','approved','rejected');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text,
  role public.user_role not null default 'merchant',
  kyc_tier public.kyc_tier not null default 'kyc1',
  kyc_status public.kyc_state not null default 'not_submitted',
  balance_available numeric(14,2) not null default 0 check(balance_available>=0),
  balance_pending numeric(14,2) not null default 0 check(balance_pending>=0),
  default_pix_key text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.transactions (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  external_id text not null, provider text not null check(provider in ('lunar','mistic')), provider_id text,
  amount numeric(14,2) not null check(amount>=2), fee numeric(14,2) not null default 0, net_amount numeric(14,2) not null default 0,
  customer_name text, customer_document text, description text, status text not null default 'creating',
  pix_code text, qr_image text, provider_payload jsonb, error_message text,
  paid_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(user_id,external_id)
);
create index transactions_user_created_idx on public.transactions(user_id,created_at desc);
create index transactions_provider_idx on public.transactions(provider,provider_id);
create table public.withdrawals (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null check(provider in ('lunar','mistic')), provider_id text, pix_key text not null, pix_key_type text not null,
  amount numeric(14,2) not null check(amount>=10), fee numeric(14,2) not null, net_amount numeric(14,2) not null,
  status text not null default 'pending_admin', approved_by uuid references public.profiles(id), approved_at timestamptz,
  provider_payload jsonb, error_message text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.kyc_submissions (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  document_front_path text not null, document_back_path text not null, selfie_path text not null,
  status text not null default 'pending', review_notes text, reviewed_by uuid references public.profiles(id), reviewed_at timestamptz, created_at timestamptz not null default now()
);
create table public.products (id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,name text not null,description text,price numeric(14,2) not null check(price>=2),active boolean not null default true,sales integer not null default 0,created_at timestamptz not null default now());
create table public.coupons (id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,code text not null,discount_type text not null check(discount_type in ('percent','fixed')),discount_value numeric(14,2) not null check(discount_value>0),active boolean not null default true,uses integer not null default 0,created_at timestamptz not null default now(),unique(user_id,code));
create table public.tickets (id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,subject text not null,message text not null,status text not null default 'open',assigned_to uuid references public.profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.ticket_messages (id uuid primary key default gen_random_uuid(),ticket_id uuid not null references public.tickets(id) on delete cascade,author_id uuid not null references public.profiles(id),message text not null,created_at timestamptz not null default now());
create table public.webhook_endpoints (id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,url text not null,events text[] not null default '{}',signing_secret text not null,active boolean not null default true,created_at timestamptz not null default now());
create table public.webhook_deliveries (id uuid primary key default gen_random_uuid(),endpoint_id uuid not null references public.webhook_endpoints(id) on delete cascade,event text not null,payload jsonb not null,status text not null default 'pending',attempts integer not null default 0,last_error text,created_at timestamptz not null default now());
create table public.med_infractions (id uuid primary key default gen_random_uuid(),user_id uuid references public.profiles(id) on delete cascade,provider_id text unique,external_id text,status text,amount numeric(14,2),payload jsonb,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.ledger_entries (id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,transaction_id uuid references public.transactions(id),withdrawal_id uuid references public.withdrawals(id),kind text not null,amount numeric(14,2) not null,balance_after numeric(14,2) not null,description text,created_at timestamptz not null default now());
create table public.webhook_events (event_key text primary key,provider text,payload jsonb not null,processed_at timestamptz not null default now());
create table public.audit_logs (id bigint generated always as identity primary key,actor_id uuid references public.profiles(id),action text not null,entity_type text,entity_id text,metadata jsonb,created_at timestamptz not null default now());

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id,email,full_name,kyc_tier,kyc_status) values(new.id,new.email,coalesce(new.raw_user_meta_data->>'full_name','Nova conta'),coalesce((new.raw_user_meta_data->>'kyc_tier')::public.kyc_tier,'kyc1'),'not_submitted');return new;end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.profiles where id=auth.uid() and role in ('admin','support'))$$;

create or replace function public.reserve_withdrawal(p_user uuid,p_provider text,p_key text,p_type text,p_amount numeric,p_fee numeric) returns public.withdrawals language plpgsql security definer set search_path=public as $$
declare p public.profiles; w public.withdrawals;
begin
  select * into p from public.profiles where id=p_user for update;
  if not found or p.balance_available < p_amount+p_fee then raise exception 'Saldo insuficiente para valor e taxa'; end if;
  update public.profiles set balance_available=balance_available-p_amount-p_fee,balance_pending=balance_pending+p_amount,updated_at=now() where id=p_user;
  insert into public.withdrawals(user_id,provider,pix_key,pix_key_type,amount,fee,net_amount,status) values(p_user,p_provider,p_key,p_type,p_amount,p_fee,p_amount,'pending_admin') returning * into w;
  insert into public.ledger_entries(user_id,withdrawal_id,kind,amount,balance_after,description) values(p_user,w.id,'withdrawal_reserve',-(p_amount+p_fee),p.balance_available-p_amount-p_fee,'Reserva de saque e taxa');
  return w;
end $$;

create or replace function public.apply_payment_event(p_event_key text,p_external_id text,p_provider_id text,p_status text,p_payload jsonb) returns void language plpgsql security definer set search_path=public as $$
declare t public.transactions; inserted integer;
begin
  insert into public.webhook_events(event_key,provider,payload) values(p_event_key,split_part(p_event_key,':',1),p_payload) on conflict do nothing;
  get diagnostics inserted = row_count; if inserted=0 then return; end if;
  select * into t from public.transactions where external_id=p_external_id or provider_id=p_provider_id order by created_at desc limit 1 for update;
  if not found then return; end if;
  if p_status='paid' and t.status<>'paid' then
    update public.transactions set status='paid',paid_at=now(),provider_payload=p_payload,updated_at=now() where id=t.id;
    update public.profiles set balance_available=balance_available+t.net_amount,updated_at=now() where id=t.user_id returning balance_available into t.net_amount;
    insert into public.ledger_entries(user_id,transaction_id,kind,amount,balance_after,description) values(t.user_id,t.id,'payment_credit',t.amount-t.fee,t.net_amount,'Venda Pix confirmada');
  else update public.transactions set status=p_status,provider_payload=p_payload,updated_at=now() where id=t.id; end if;
end $$;

create or replace function public.apply_withdrawal_event(p_event_key text,p_external_id text,p_provider_id text,p_status text,p_payload jsonb) returns void language plpgsql security definer set search_path=public as $$
declare w public.withdrawals; inserted integer; current_balance numeric;
begin
  insert into public.webhook_events(event_key,provider,payload) values(p_event_key,split_part(p_event_key,':',1),p_payload) on conflict do nothing;
  get diagnostics inserted = row_count; if inserted=0 then return; end if;
  select * into w from public.withdrawals where provider_id=p_provider_id or id::text=p_external_id order by created_at desc limit 1 for update;
  if not found then return; end if;
  if p_status in ('completed','paid') and w.status<>'completed' then
    update public.withdrawals set status='completed',provider_payload=p_payload,updated_at=now() where id=w.id;
    update public.profiles set balance_pending=greatest(0,balance_pending-w.amount),updated_at=now() where id=w.user_id returning balance_available into current_balance;
    insert into public.ledger_entries(user_id,withdrawal_id,kind,amount,balance_after,description) values(w.user_id,w.id,'withdrawal_completed',0,current_balance,'Saque Pix concluído');
  elsif p_status in ('failed','cancelled','refunded') and w.status not in ('failed','cancelled','refunded') then
    update public.withdrawals set status=p_status,provider_payload=p_payload,updated_at=now() where id=w.id;
    update public.profiles set balance_available=balance_available+w.amount+w.fee,balance_pending=greatest(0,balance_pending-w.amount),updated_at=now() where id=w.user_id returning balance_available into current_balance;
    insert into public.ledger_entries(user_id,withdrawal_id,kind,amount,balance_after,description) values(w.user_id,w.id,'withdrawal_release',w.amount+w.fee,current_balance,'Reserva devolvida');
  else update public.withdrawals set status=p_status,provider_payload=p_payload,updated_at=now() where id=w.id; end if;
end $$;

create or replace function public.release_withdrawal_reserve(p_withdrawal uuid,p_reason text) returns void language plpgsql security definer set search_path=public as $$
declare w public.withdrawals; current_balance numeric;
begin
  select * into w from public.withdrawals where id=p_withdrawal for update;
  if not found or w.status in ('completed','failed','cancelled','rejected') then return; end if;
  update public.withdrawals set status='provider_error',error_message=p_reason,updated_at=now() where id=w.id;
  update public.profiles set balance_available=balance_available+w.amount+w.fee,balance_pending=greatest(0,balance_pending-w.amount),updated_at=now() where id=w.user_id returning balance_available into current_balance;
  insert into public.ledger_entries(user_id,withdrawal_id,kind,amount,balance_after,description) values(w.user_id,w.id,'withdrawal_release',w.amount+w.fee,current_balance,'Falha no provedor; reserva devolvida');
end $$;

alter table public.profiles enable row level security;alter table public.transactions enable row level security;alter table public.withdrawals enable row level security;alter table public.kyc_submissions enable row level security;alter table public.products enable row level security;alter table public.coupons enable row level security;alter table public.tickets enable row level security;alter table public.ticket_messages enable row level security;alter table public.webhook_endpoints enable row level security;alter table public.webhook_deliveries enable row level security;alter table public.med_infractions enable row level security;alter table public.ledger_entries enable row level security;alter table public.audit_logs enable row level security;
create policy "own profile" on public.profiles for select using(id=auth.uid() or public.is_admin());
create policy "own transactions" on public.transactions for select using(user_id=auth.uid() or public.is_admin());
create policy "own withdrawals" on public.withdrawals for select using(user_id=auth.uid() or public.is_admin());
create policy "own kyc insert" on public.kyc_submissions for insert with check(user_id=auth.uid());create policy "own kyc read" on public.kyc_submissions for select using(user_id=auth.uid() or public.is_admin());
create policy "own products read" on public.products for select using(user_id=auth.uid() or public.is_admin());create policy "own coupons read" on public.coupons for select using(user_id=auth.uid() or public.is_admin());
create policy "own tickets" on public.tickets for select using(user_id=auth.uid() or public.is_admin());create policy "ticket messages" on public.ticket_messages for select using(exists(select 1 from public.tickets t where t.id=ticket_id and (t.user_id=auth.uid() or public.is_admin())));
create policy "own endpoints" on public.webhook_endpoints for select using(user_id=auth.uid() or public.is_admin());create policy "own deliveries" on public.webhook_deliveries for select using(exists(select 1 from public.webhook_endpoints e where e.id=endpoint_id and (e.user_id=auth.uid() or public.is_admin())));
create policy "own med" on public.med_infractions for select using(user_id=auth.uid() or public.is_admin());create policy "own ledger" on public.ledger_entries for select using(user_id=auth.uid() or public.is_admin());create policy "admin audit" on public.audit_logs for select using(public.is_admin());

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('kyc-documents','kyc-documents',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf']) on conflict(id) do nothing;
create policy "upload own kyc" on storage.objects for insert to authenticated with check(bucket_id='kyc-documents' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "read own kyc" on storage.objects for select to authenticated using(bucket_id='kyc-documents' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));

-- Depois de criar o primeiro usuário, promova o administrador:
-- update public.profiles set role='admin' where email='admin@seudominio.com';

