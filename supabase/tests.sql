-- Vadio Cellar - Quick SQL Tests (run after master_migration.sql)
-- These tests assume authenticated context with admin/operator profile.

begin;

-- Setup test fixtures
insert into public.vineyard_block(code, name, area_ha) values ('TALH1', 'Talhao 1', 2.1) on conflict (code) do nothing;
insert into public.vineyard_block(code, name, area_ha) values ('TALH2', 'Talhao 2', 1.4) on conflict (code) do nothing;
insert into public.grape_variety(code, name) values ('BAGA', 'Baga') on conflict (code) do nothing;
insert into public.grape_variety(code, name) values ('TOUR', 'Touriga Nacional') on conflict (code) do nothing;
insert into public.tank(tank_code, tank_type, capacity_l) values ('A01', 'A', 5000) on conflict (tank_code) do nothing;
insert into public.tank(tank_code, tank_type, capacity_l) values ('F01', 'F', 3000) on conflict (tank_code) do nothing;
insert into public.tank(tank_code, tank_type, capacity_l) values ('F02', 'F', 3000) on conflict (tank_code) do nothing;
insert into public.tank(tank_code, tank_type, capacity_l) values ('A02', 'A', 5000) on conflict (tank_code) do nothing;

do $$
declare
  v_code_1 text;
  v_code_2 text;
  v_2026 text;
  v_tank_a01 uuid;
  v_tank_f01 uuid;
  v_tank_f02 uuid;
  v_tank_a02 uuid;
  v_block1 uuid;
  v_block2 uuid;
  v_baga uuid;
  v_tour uuid;
  v_batch_grape1 uuid;
  v_batch_grape2 uuid;
  v_batch_must1 uuid;
  v_batch_must2 uuid;
  v_batch_blend uuid;
  v_batch_bottle uuid;
  v_count int;
  v_product uuid;
  v_product_lot uuid;
  v_event uuid;
begin
  select id into v_tank_a01 from public.tank where tank_code = 'A01';
  select id into v_tank_f01 from public.tank where tank_code = 'F01';
  select id into v_tank_f02 from public.tank where tank_code = 'F02';
  select id into v_tank_a02 from public.tank where tank_code = 'A02';
  select id into v_block1 from public.vineyard_block where code = 'TALH1';
  select id into v_block2 from public.vineyard_block where code = 'TALH2';
  select id into v_baga from public.grape_variety where code = 'BAGA';
  select id into v_tour from public.grape_variety where code = 'TOUR';

  -- Test 1: yearly sequence reset
  v_code_1 := public.next_internal_lot_code('2025-09-01');
  v_code_2 := public.next_internal_lot_code('2025-09-02');
  v_2026 := public.next_internal_lot_code('2026-01-01');
  if v_code_1 not like 'L25%' or v_code_2 not like 'L25%' or v_2026 not like 'L26%' then
    raise exception 'Test 1 failed: lot code yearly sequence';
  end if;

  -- Test 2: pressing inherits batch_component origin
  insert into public.batch(phase, internal_code, tank_id, current_volume_l) values ('GRAPE', public.next_internal_lot_code(now()), v_tank_a01, 1000) returning id into v_batch_grape1;
  insert into public.batch_component(batch_id, block_id, variety_id, qty_kg) values (v_batch_grape1, v_block1, v_baga, 800);
  v_batch_must1 := public.rpc_press_to_must(v_batch_grape1, v_tank_f01, 700, 'G', 'test press');
  select count(*) into v_count from public.batch_component where batch_id = v_batch_must1 and block_id = v_block1 and variety_id = v_baga and qty_kg = 800;
  if v_count <> 1 then
    raise exception 'Test 2 failed: component inheritance';
  end if;

  -- Test 3: blend aggregates origin quantities
  insert into public.batch(phase, internal_code, tank_id, current_volume_l) values ('GRAPE', public.next_internal_lot_code(now()), v_tank_f02, 900) returning id into v_batch_grape2;
  insert into public.batch_component(batch_id, block_id, variety_id, qty_kg) values (v_batch_grape2, v_block2, v_tour, 600);
  v_batch_must2 := public.rpc_press_to_must(v_batch_grape2, v_tank_a02, 600, 'G', 'test press 2');
  v_batch_blend := public.rpc_blend_batches(array[v_batch_must1, v_batch_must2], v_tank_a01, 1200, 'blend test');
  select count(*) into v_count from public.batch_component where batch_id = v_batch_blend;
  if v_count <> 2 then
    raise exception 'Test 3 failed: blend origin aggregation';
  end if;

  -- Test 4: manual bottling code unique
  v_batch_bottle := public.rpc_bottle_batch(v_batch_blend, 'LVT25', 1100, 10, 'bottling test');
  begin
    perform public.rpc_bottle_batch(v_batch_must1, 'LVT25', 500, 0, 'dup lot');
    raise exception 'Test 4 failed: duplicate manual lot should not pass';
  exception
    when others then
      null;
  end;

  -- Test 5: addition creates stock move OUT
  insert into public.oeno_product(code, name, default_uom)
  values ('META', 'Metabisulfito', 'kg')
  on conflict (code) do nothing;
  select id into v_product from public.oeno_product where code = 'META';

  insert into public.oeno_product_lot(product_id, supplier_lot_code)
  values (v_product, 'LOT-A')
  on conflict (product_id, supplier_lot_code) do nothing;
  select id into v_product_lot from public.oeno_product_lot where product_id = v_product and supplier_lot_code = 'LOT-A';
  insert into public.oeno_stock_move(product_lot_id, move_type, qty) values (v_product_lot, 'IN', 10);
  insert into public.batch(phase, internal_code, tank_id, current_volume_l) values ('WINE', public.next_internal_lot_code(now()), v_tank_a02, 1000) returning id into v_batch_grape1;
  v_event := public.rpc_addition(v_batch_grape1, v_tank_a02, v_product_lot, 2, 'kg', 'test addition');
  select count(*) into v_count from public.oeno_stock_move where ref_event_id = v_event and move_type = 'OUT' and qty = 2;
  if v_count <> 1 then
    raise exception 'Test 5 failed: stock OUT not created';
  end if;
end;
$$;

rollback;
