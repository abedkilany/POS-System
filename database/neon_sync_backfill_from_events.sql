-- Backfill entity_snapshots from already uploaded restore_snapshot events.
-- Run this once if sync_events has restore_snapshot rows but entity_snapshots is empty.

insert into entity_snapshots (store_id, branch_id, entity_type, entity_id, payload, operation, updated_at)
select se.store_id, coalesce(se.branch_id, 'main'), 'product', item->>'id', item, 'upsert', se.created_at
from sync_events se, jsonb_array_elements(coalesce(se.payload->'products', '[]'::jsonb)) item
where se.operation = 'restore_snapshot' and item ? 'id'
on conflict (store_id, branch_id, entity_type, entity_id) do update set payload = excluded.payload, operation = excluded.operation, updated_at = excluded.updated_at;

insert into entity_snapshots (store_id, branch_id, entity_type, entity_id, payload, operation, updated_at)
select se.store_id, coalesce(se.branch_id, 'main'), 'customer', item->>'id', item, 'upsert', se.created_at
from sync_events se, jsonb_array_elements(coalesce(se.payload->'customers', '[]'::jsonb)) item
where se.operation = 'restore_snapshot' and item ? 'id'
on conflict (store_id, branch_id, entity_type, entity_id) do update set payload = excluded.payload, operation = excluded.operation, updated_at = excluded.updated_at;

insert into entity_snapshots (store_id, branch_id, entity_type, entity_id, payload, operation, updated_at)
select se.store_id, coalesce(se.branch_id, 'main'), 'sale', item->>'id', item, 'upsert', se.created_at
from sync_events se, jsonb_array_elements(coalesce(se.payload->'sales', '[]'::jsonb)) item
where se.operation = 'restore_snapshot' and item ? 'id'
on conflict (store_id, branch_id, entity_type, entity_id) do update set payload = excluded.payload, operation = excluded.operation, updated_at = excluded.updated_at;

insert into entity_snapshots (store_id, branch_id, entity_type, entity_id, payload, operation, updated_at)
select se.store_id, coalesce(se.branch_id, 'main'), 'supplier', item->>'id', item, 'upsert', se.created_at
from sync_events se, jsonb_array_elements(coalesce(se.payload->'suppliers', '[]'::jsonb)) item
where se.operation = 'restore_snapshot' and item ? 'id'
on conflict (store_id, branch_id, entity_type, entity_id) do update set payload = excluded.payload, operation = excluded.operation, updated_at = excluded.updated_at;

insert into entity_snapshots (store_id, branch_id, entity_type, entity_id, payload, operation, updated_at)
select se.store_id, coalesce(se.branch_id, 'main'), 'expense', item->>'id', item, 'upsert', se.created_at
from sync_events se, jsonb_array_elements(coalesce(se.payload->'expenses', '[]'::jsonb)) item
where se.operation = 'restore_snapshot' and item ? 'id'
on conflict (store_id, branch_id, entity_type, entity_id) do update set payload = excluded.payload, operation = excluded.operation, updated_at = excluded.updated_at;

insert into entity_snapshots (store_id, branch_id, entity_type, entity_id, payload, operation, updated_at)
select se.store_id, coalesce(se.branch_id, 'main'), 'category', item->>'id', item, 'upsert', se.created_at
from sync_events se, jsonb_array_elements(coalesce(se.payload->'categories', '[]'::jsonb)) item
where se.operation = 'restore_snapshot' and item ? 'id'
on conflict (store_id, branch_id, entity_type, entity_id) do update set payload = excluded.payload, operation = excluded.operation, updated_at = excluded.updated_at;

insert into entity_snapshots (store_id, branch_id, entity_type, entity_id, payload, operation, updated_at)
select se.store_id, coalesce(se.branch_id, 'main'), 'brand', item->>'id', item, 'upsert', se.created_at
from sync_events se, jsonb_array_elements(coalesce(se.payload->'brands', '[]'::jsonb)) item
where se.operation = 'restore_snapshot' and item ? 'id'
on conflict (store_id, branch_id, entity_type, entity_id) do update set payload = excluded.payload, operation = excluded.operation, updated_at = excluded.updated_at;

insert into entity_snapshots (store_id, branch_id, entity_type, entity_id, payload, operation, updated_at)
select se.store_id, coalesce(se.branch_id, 'main'), 'unit', item->>'id', item, 'upsert', se.created_at
from sync_events se, jsonb_array_elements(coalesce(se.payload->'units', '[]'::jsonb)) item
where se.operation = 'restore_snapshot' and item ? 'id'
on conflict (store_id, branch_id, entity_type, entity_id) do update set payload = excluded.payload, operation = excluded.operation, updated_at = excluded.updated_at;

insert into entity_snapshots (store_id, branch_id, entity_type, entity_id, payload, operation, updated_at)
select se.store_id, coalesce(se.branch_id, 'main'), 'role', item->>'id', item, 'upsert', se.created_at
from sync_events se, jsonb_array_elements(coalesce(se.payload->'roles', '[]'::jsonb)) item
where se.operation = 'restore_snapshot' and item ? 'id'
on conflict (store_id, branch_id, entity_type, entity_id) do update set payload = excluded.payload, operation = excluded.operation, updated_at = excluded.updated_at;

insert into entity_snapshots (store_id, branch_id, entity_type, entity_id, payload, operation, updated_at)
select se.store_id, coalesce(se.branch_id, 'main'), 'user', item->>'id', item, 'upsert', se.created_at
from sync_events se, jsonb_array_elements(coalesce(se.payload->'users', '[]'::jsonb)) item
where se.operation = 'restore_snapshot' and item ? 'id'
on conflict (store_id, branch_id, entity_type, entity_id) do update set payload = excluded.payload, operation = excluded.operation, updated_at = excluded.updated_at;

insert into entity_snapshots (store_id, branch_id, entity_type, entity_id, payload, operation, updated_at)
select se.store_id, coalesce(se.branch_id, 'main'), 'store_profile', 'store', se.payload->'storeProfile', 'upsert', se.created_at
from sync_events se
where se.operation = 'restore_snapshot' and se.payload ? 'storeProfile'
on conflict (store_id, branch_id, entity_type, entity_id) do update set payload = excluded.payload, operation = excluded.operation, updated_at = excluded.updated_at;
