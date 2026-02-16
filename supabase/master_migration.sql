-- Vadio Cellar - Master Migration
-- Run in Supabase SQL editor as a single migration

create extension if not exists "pgcrypto";

create type public.app_role as enum ('admin', 'operator');
create type public.batch_phase as enum ('GRAPE', 'MUST', 'WINE', 'BOTTLED');
create type public.batch_status as enum ('ACTIVE', 'CLOSED');
create type public.tank_type as enum ('A', 'F', 'BARR', 'T', 'B', 'OTHER');
create type public.event_type as enum (
  'INTAKE',
  'PRESSING',
  'TRANSFER',
  'BLEND',
  'ADDITION',
  'BOTTLING',
  'HACCP',
  'ANALYSIS',
  'OTHER'
);
create type public.stock_move_type as enum ('IN', 'OUT', 'ADJUST');

create table if not exists public.profile (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  role public.app_role not null default 'operator',
  created_at timestamptz not null default now()
);

create table if not exists public.vineyard_block (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  area_ha numeric(8, 3),
  soil text,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.grape_variety (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.tank (
  id uuid primary key default gen_random_uuid(),
  tank_code text not null unique,
  tank_type public.tank_type not null,
  capacity_l numeric(12, 2) not null check (capacity_l > 0),
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.equipment (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  is_haccp_relevant boolean not null default true,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.batch_year_seq (
  lot_year int primary key,
  last_seq int not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.batch (
  id uuid primary key default gen_random_uuid(),
  phase public.batch_phase not null,
  status public.batch_status not null default 'ACTIVE',
  internal_code text unique,
  manual_code text unique,
  tank_id uuid references public.tank (id),
  current_volume_l numeric(12, 2) not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  closed_at timestamptz
);

create unique index if not exists uq_batch_active_per_tank
  on public.batch (tank_id)
  where status = 'ACTIVE' and tank_id is not null;

create table if not exists public.intake (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.batch (id) on delete cascade,
  intake_at timestamptz not null default now(),
  vineyard_block_id uuid not null references public.vineyard_block (id),
  variety_id uuid not null references public.grape_variety (id),
  qty_kg numeric(12, 3) not null check (qty_kg > 0),
  notes text,
  created_by uuid references auth.users (id)
);

create table if not exists public.batch_component (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.batch (id) on delete cascade,
  block_id uuid not null references public.vineyard_block (id),
  variety_id uuid not null references public.grape_variety (id),
  qty_kg numeric(12, 3) not null check (qty_kg > 0),
  source_intake_id uuid references public.intake (id),
  created_at timestamptz not null default now()
);

create table if not exists public.cellar_event (
  id uuid primary key default gen_random_uuid(),
  event_type public.event_type not null,
  occurred_at timestamptz not null default now(),
  from_batch_id uuid references public.batch (id),
  to_batch_id uuid references public.batch (id),
  from_tank_id uuid references public.tank (id),
  to_tank_id uuid references public.tank (id),
  volume_l numeric(12, 2),
  loss_l numeric(12, 2) default 0,
  fraction_label text,
  notes text,
  created_by uuid references auth.users (id)
);

create table if not exists public.analysis_parameter (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  label text not null,
  unit text,
  min_value numeric,
  max_value numeric,
  is_active boolean not null default true
);

create table if not exists public.analysis_reading (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.batch (id) on delete cascade,
  tank_id uuid references public.tank (id),
  parameter_id uuid not null references public.analysis_parameter (id),
  value_num numeric(14, 6),
  value_text text,
  measured_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  check (value_num is not null or value_text is not null)
);

create table if not exists public.haccp_cleaning (
  id uuid primary key default gen_random_uuid(),
  cleaned_at timestamptz not null default now(),
  tank_id uuid references public.tank (id),
  equipment_id uuid references public.equipment (id),
  method text not null,
  chemical text,
  concentration text,
  contact_time_min int,
  responsible_name text not null,
  notes text,
  created_by uuid references auth.users (id),
  check (tank_id is not null or equipment_id is not null)
);

create table if not exists public.oeno_product (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  default_uom text not null default 'kg',
  created_at timestamptz not null default now()
);

create table if not exists public.oeno_product_lot (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.oeno_product (id) on delete cascade,
  supplier_lot_code text not null,
  expires_on date,
  unique (product_id, supplier_lot_code)
);

create table if not exists public.oeno_stock_move (
  id uuid primary key default gen_random_uuid(),
  product_lot_id uuid not null references public.oeno_product_lot (id) on delete cascade,
  move_type public.stock_move_type not null,
  qty numeric(12, 3) not null check (qty > 0),
  occurred_at timestamptz not null default now(),
  ref_event_id uuid references public.cellar_event (id),
  notes text,
  created_by uuid references auth.users (id)
);

create table if not exists public.addition_detail (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.cellar_event (id) on delete cascade,
  batch_id uuid not null references public.batch (id) on delete cascade,
  tank_id uuid references public.tank (id),
  product_lot_id uuid not null references public.oeno_product_lot (id),
  qty numeric(12, 3) not null check (qty > 0),
  uom text not null default 'kg',
  notes text
);

create or replace function public.current_user_is_admin()
returns boolean
language sql
stable
as $$
  select auth.role() = 'service_role' or exists (
    select 1 from public.profile p
    where p.id = auth.uid() and p.role = 'admin'
  );
$$;

create or replace function public.current_user_is_operator_or_admin()
returns boolean
language sql
stable
as $$
  select auth.role() = 'service_role' or exists (
    select 1 from public.profile p
    where p.id = auth.uid() and p.role in ('admin', 'operator')
  );
$$;

create or replace function public.next_internal_lot_code(p_event_at timestamptz default now())
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year int;
  v_next int;
begin
  v_year := extract(year from p_event_at)::int;

  insert into public.batch_year_seq(lot_year, last_seq)
  values (v_year, 1)
  on conflict (lot_year)
  do update set
    last_seq = public.batch_year_seq.last_seq + 1,
    updated_at = now()
  returning last_seq into v_next;

  return 'L' || to_char((v_year % 100), 'FM00') || to_char(v_next, 'FM000');
end;
$$;

create or replace function public.rpc_create_intake(
  p_tank_id uuid,
  p_block_id uuid,
  p_variety_id uuid,
  p_qty_kg numeric,
  p_volume_l numeric,
  p_notes text default null,
  p_intake_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch_id uuid;
  v_lot text;
  v_intake_id uuid;
begin
  if not public.current_user_is_operator_or_admin() then
    raise exception 'Not allowed';
  end if;

  v_lot := public.next_internal_lot_code(p_intake_at);

  insert into public.batch(phase, status, internal_code, tank_id, current_volume_l, notes)
  values ('GRAPE', 'ACTIVE', v_lot, p_tank_id, coalesce(p_volume_l, 0), p_notes)
  returning id into v_batch_id;

  insert into public.intake(batch_id, intake_at, vineyard_block_id, variety_id, qty_kg, notes, created_by)
  values (v_batch_id, p_intake_at, p_block_id, p_variety_id, p_qty_kg, p_notes, auth.uid())
  returning id into v_intake_id;

  insert into public.batch_component(batch_id, block_id, variety_id, qty_kg, source_intake_id)
  values (v_batch_id, p_block_id, p_variety_id, p_qty_kg, v_intake_id);

  insert into public.cellar_event(event_type, occurred_at, to_batch_id, to_tank_id, volume_l, notes, created_by)
  values ('INTAKE', p_intake_at, v_batch_id, p_tank_id, p_volume_l, p_notes, auth.uid());

  return v_batch_id;
end;
$$;

create or replace function public.rpc_press_to_must(
  p_source_batch_id uuid,
  p_to_tank_id uuid,
  p_volume_l numeric,
  p_fraction_label text default null,
  p_notes text default null,
  p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_batch_id uuid;
  v_lot text;
begin
  if not public.current_user_is_operator_or_admin() then
    raise exception 'Not allowed';
  end if;

  v_lot := public.next_internal_lot_code(p_occurred_at);

  insert into public.batch(phase, status, internal_code, tank_id, current_volume_l, notes)
  values ('MUST', 'ACTIVE', v_lot, p_to_tank_id, p_volume_l, p_notes)
  returning id into v_new_batch_id;

  insert into public.batch_component(batch_id, block_id, variety_id, qty_kg, source_intake_id)
  select
    v_new_batch_id,
    bc.block_id,
    bc.variety_id,
    sum(bc.qty_kg),
    min(bc.source_intake_id)
  from public.batch_component bc
  where bc.batch_id = p_source_batch_id
  group by bc.block_id, bc.variety_id;

  insert into public.cellar_event(event_type, occurred_at, from_batch_id, to_batch_id, from_tank_id, to_tank_id, volume_l, fraction_label, notes, created_by)
  select 'PRESSING', p_occurred_at, p_source_batch_id, v_new_batch_id, b.tank_id, p_to_tank_id, p_volume_l, p_fraction_label, p_notes, auth.uid()
  from public.batch b
  where b.id = p_source_batch_id;

  return v_new_batch_id;
end;
$$;

create or replace function public.rpc_transfer_batch(
  p_batch_id uuid,
  p_to_tank_id uuid,
  p_new_volume_l numeric,
  p_loss_l numeric default 0,
  p_notes text default null,
  p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from_tank_id uuid;
begin
  if not public.current_user_is_operator_or_admin() then
    raise exception 'Not allowed';
  end if;

  select tank_id into v_from_tank_id from public.batch where id = p_batch_id and status = 'ACTIVE';
  if v_from_tank_id is null then
    raise exception 'Batch not active or not found';
  end if;

  update public.batch
  set tank_id = p_to_tank_id,
      current_volume_l = p_new_volume_l
  where id = p_batch_id;

  insert into public.cellar_event(event_type, occurred_at, from_batch_id, to_batch_id, from_tank_id, to_tank_id, volume_l, loss_l, notes, created_by)
  values ('TRANSFER', p_occurred_at, p_batch_id, p_batch_id, v_from_tank_id, p_to_tank_id, p_new_volume_l, coalesce(p_loss_l, 0), p_notes, auth.uid());

  return p_batch_id;
end;
$$;

create or replace function public.rpc_blend_batches(
  p_source_batch_ids uuid[],
  p_to_tank_id uuid,
  p_total_volume_l numeric,
  p_notes text default null,
  p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_batch_id uuid;
  v_lot text;
begin
  if not public.current_user_is_operator_or_admin() then
    raise exception 'Not allowed';
  end if;

  v_lot := public.next_internal_lot_code(p_occurred_at);

  insert into public.batch(phase, status, internal_code, tank_id, current_volume_l, notes)
  values ('WINE', 'ACTIVE', v_lot, p_to_tank_id, p_total_volume_l, p_notes)
  returning id into v_new_batch_id;

  insert into public.batch_component(batch_id, block_id, variety_id, qty_kg, source_intake_id)
  select
    v_new_batch_id,
    bc.block_id,
    bc.variety_id,
    sum(bc.qty_kg),
    min(bc.source_intake_id)
  from public.batch_component bc
  where bc.batch_id = any(p_source_batch_ids)
  group by bc.block_id, bc.variety_id;

  insert into public.cellar_event(event_type, occurred_at, from_batch_id, to_batch_id, to_tank_id, volume_l, notes, created_by)
  select 'BLEND', p_occurred_at, b.id, v_new_batch_id, p_to_tank_id, p_total_volume_l, p_notes, auth.uid()
  from public.batch b
  where b.id = any(p_source_batch_ids);

  return v_new_batch_id;
end;
$$;

create or replace function public.rpc_bottle_batch(
  p_batch_id uuid,
  p_manual_lot_code text,
  p_bottled_volume_l numeric,
  p_loss_l numeric default 0,
  p_notes text default null,
  p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tank_id uuid;
begin
  if not public.current_user_is_operator_or_admin() then
    raise exception 'Not allowed';
  end if;

  if exists(select 1 from public.batch where manual_code = p_manual_lot_code and id <> p_batch_id) then
    raise exception 'Manual lot code already exists';
  end if;

  select tank_id into v_tank_id from public.batch where id = p_batch_id;

  update public.batch
  set phase = 'BOTTLED',
      status = 'CLOSED',
      manual_code = p_manual_lot_code,
      current_volume_l = p_bottled_volume_l,
      closed_at = p_occurred_at,
      notes = coalesce(p_notes, notes)
  where id = p_batch_id;

  insert into public.cellar_event(event_type, occurred_at, from_batch_id, from_tank_id, volume_l, loss_l, notes, created_by)
  values ('BOTTLING', p_occurred_at, p_batch_id, v_tank_id, p_bottled_volume_l, coalesce(p_loss_l, 0), p_notes, auth.uid());

  return p_batch_id;
end;
$$;

create or replace function public.rpc_addition(
  p_batch_id uuid,
  p_tank_id uuid,
  p_product_lot_id uuid,
  p_qty numeric,
  p_uom text default 'kg',
  p_notes text default null,
  p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_id uuid;
begin
  if not public.current_user_is_operator_or_admin() then
    raise exception 'Not allowed';
  end if;

  insert into public.cellar_event(event_type, occurred_at, to_batch_id, to_tank_id, notes, created_by)
  values ('ADDITION', p_occurred_at, p_batch_id, p_tank_id, p_notes, auth.uid())
  returning id into v_event_id;

  insert into public.addition_detail(event_id, batch_id, tank_id, product_lot_id, qty, uom, notes)
  values (v_event_id, p_batch_id, p_tank_id, p_product_lot_id, p_qty, p_uom, p_notes);

  insert into public.oeno_stock_move(product_lot_id, move_type, qty, occurred_at, ref_event_id, notes, created_by)
  values (p_product_lot_id, 'OUT', p_qty, p_occurred_at, v_event_id, p_notes, auth.uid());

  return v_event_id;
end;
$$;

create or replace view public.v_dashboard_tanks as
with latest_density as (
  select
    ar.batch_id,
    ar.value_num as density,
    row_number() over (partition by ar.batch_id order by ar.measured_at desc) as rn
  from public.analysis_reading ar
  join public.analysis_parameter ap on ap.id = ar.parameter_id
  where ap.code = 'density' and ar.value_num is not null
)
select
  t.id as tank_id,
  t.tank_code,
  t.tank_type,
  t.capacity_l,
  b.id as batch_id,
  coalesce(b.manual_code, b.internal_code) as lot_code,
  b.phase,
  b.current_volume_l as volume_l,
  round(case when t.capacity_l > 0 then (b.current_volume_l / t.capacity_l) * 100 else 0 end, 2) as fill_pct,
  case
    when b.id is null then 'EMPTY'
    when coalesce(b.current_volume_l, 0) = 0 then 'ZERO_VOLUME'
    when b.current_volume_l > t.capacity_l then 'OVER_100%'
    when b.current_volume_l >= (t.capacity_l * 0.95) then 'OVER_95%'
    else 'OK'
  end as alert,
  ld.density,
  case
    when t.tank_code ~ '^[A-Z]+' then regexp_replace(t.tank_code, '([0-9].*)$', '')
    else t.tank_code
  end as sort_prefix,
  coalesce(nullif(regexp_replace(t.tank_code, '^[^0-9]*', ''), '')::int, 0) as sort_number
from public.tank t
left join public.batch b
  on b.tank_id = t.id and b.status = 'ACTIVE'
left join latest_density ld
  on ld.batch_id = b.id and ld.rn = 1
where t.is_active = true;

create or replace view public.v_fermentation_active as
select
  d.*,
  ap.label as density_label,
  ap.unit as density_unit
from public.v_dashboard_tanks d
join public.analysis_parameter ap on ap.code = 'density'
where d.tank_code like 'F%'
  and d.phase = 'MUST'
  and coalesce(d.density, 0) > 0.995;

create or replace view public.v_fermentation_finished_recent as
select
  ce.id as event_id,
  ce.occurred_at,
  t.tank_code,
  b.internal_code as lot_code,
  b.phase,
  ce.notes
from public.cellar_event ce
join public.batch b on b.id = ce.to_batch_id
left join public.tank t on t.id = ce.to_tank_id
where ce.event_type = 'TRANSFER'
  and b.phase = 'WINE'
  and ce.occurred_at >= now() - interval '14 days';

create or replace view public.v_fermentation_missing_readings as
select
  d.tank_id,
  d.tank_code,
  d.batch_id,
  d.lot_code,
  d.phase
from public.v_dashboard_tanks d
where d.tank_code like 'F%'
  and d.phase = 'MUST'
  and d.density is null;

alter table public.profile enable row level security;
alter table public.vineyard_block enable row level security;
alter table public.grape_variety enable row level security;
alter table public.tank enable row level security;
alter table public.equipment enable row level security;
alter table public.batch enable row level security;
alter table public.intake enable row level security;
alter table public.batch_component enable row level security;
alter table public.cellar_event enable row level security;
alter table public.analysis_parameter enable row level security;
alter table public.analysis_reading enable row level security;
alter table public.haccp_cleaning enable row level security;
alter table public.oeno_product enable row level security;
alter table public.oeno_product_lot enable row level security;
alter table public.oeno_stock_move enable row level security;
alter table public.addition_detail enable row level security;

create policy "profile self read"
on public.profile for select
to authenticated
using (id = auth.uid() or public.current_user_is_admin());

create policy "profile self upsert"
on public.profile for insert
to authenticated
with check (id = auth.uid() or public.current_user_is_admin());

create policy "profile self update"
on public.profile for update
to authenticated
using (id = auth.uid() or public.current_user_is_admin())
with check (id = auth.uid() or public.current_user_is_admin());

create policy "read all vineyard_block"
on public.vineyard_block for select
to authenticated
using (true);

create policy "admin write vineyard_block"
on public.vineyard_block for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

create policy "read all grape_variety"
on public.grape_variety for select
to authenticated
using (true);

create policy "admin write grape_variety"
on public.grape_variety for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

create policy "read all tank"
on public.tank for select
to authenticated
using (true);

create policy "admin write tank"
on public.tank for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

create policy "read all equipment"
on public.equipment for select
to authenticated
using (true);

create policy "admin write equipment"
on public.equipment for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

create policy "read all analysis parameter"
on public.analysis_parameter for select
to authenticated
using (true);

create policy "admin write analysis parameter"
on public.analysis_parameter for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

create policy "read all oeno_product"
on public.oeno_product for select
to authenticated
using (true);

create policy "admin write oeno_product"
on public.oeno_product for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

create policy "read all oeno_product_lot"
on public.oeno_product_lot for select
to authenticated
using (true);

create policy "admin write oeno_product_lot"
on public.oeno_product_lot for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

create policy "read transactional data"
on public.batch for select to authenticated using (true);
create policy "read transactional intake"
on public.intake for select to authenticated using (true);
create policy "read transactional component"
on public.batch_component for select to authenticated using (true);
create policy "read transactional events"
on public.cellar_event for select to authenticated using (true);
create policy "read transactional analysis"
on public.analysis_reading for select to authenticated using (true);
create policy "read transactional haccp"
on public.haccp_cleaning for select to authenticated using (true);
create policy "read transactional oeno_moves"
on public.oeno_stock_move for select to authenticated using (true);
create policy "read transactional addition_detail"
on public.addition_detail for select to authenticated using (true);

create policy "operator insert analysis"
on public.analysis_reading for insert
to authenticated
with check (public.current_user_is_operator_or_admin());

create policy "operator insert haccp"
on public.haccp_cleaning for insert
to authenticated
with check (public.current_user_is_operator_or_admin());

grant usage on schema public to anon, authenticated;
grant select on public.v_dashboard_tanks to authenticated;
grant select on public.v_fermentation_active to authenticated;
grant select on public.v_fermentation_finished_recent to authenticated;
grant select on public.v_fermentation_missing_readings to authenticated;

grant execute on function public.next_internal_lot_code(timestamptz) to authenticated;
grant execute on function public.rpc_create_intake(uuid, uuid, uuid, numeric, numeric, text, timestamptz) to authenticated;
grant execute on function public.rpc_press_to_must(uuid, uuid, numeric, text, text, timestamptz) to authenticated;
grant execute on function public.rpc_transfer_batch(uuid, uuid, numeric, numeric, text, timestamptz) to authenticated;
grant execute on function public.rpc_blend_batches(uuid[], uuid, numeric, text, timestamptz) to authenticated;
grant execute on function public.rpc_bottle_batch(uuid, text, numeric, numeric, text, timestamptz) to authenticated;
grant execute on function public.rpc_addition(uuid, uuid, uuid, numeric, text, text, timestamptz) to authenticated;

insert into public.analysis_parameter(code, label, unit, min_value, max_value)
values
  ('density', 'Densidade', 'g/mL', 0.900, 1.200),
  ('temp_c', 'Temperatura', 'ºC', -5, 60),
  ('ph', 'pH', null, 2.5, 4.5),
  ('total_acidity', 'Acidez Total', 'g/L', 0, 20),
  ('volatile_acidity', 'Acidez Volátil', 'g/L', 0, 5),
  ('alcohol_pct', 'Álcool', '%', 0, 20)
on conflict (code) do nothing;

insert into public.equipment(code, name)
values
  ('PRESS', 'Prensa'),
  ('FILTER', 'Filtro'),
  ('FILL', 'Enchimento'),
  ('HOSE_GEN', 'Mangueira genérica')
on conflict (code) do nothing;
