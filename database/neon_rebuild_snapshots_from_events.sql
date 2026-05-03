-- Rebuild entity_snapshots from sync_events, including stock_movement events.
-- Use this if you already pushed events before this patched API was deployed.
-- It preserves sync_events and fully regenerates latest snapshots per store.

begin;
truncate table entity_snapshots;

-- Latest non-stock entity state.
insert into entity_snapshots (store_id, entity_type, entity_id, payload, operation, updated_at)
select distinct on (store_id, entity_type, entity_id)
  store_id,
  entity_type,
  entity_id,
  payload,
  case when operation = 'delete' then 'delete' else 'upsert' end,
  created_at
from sync_events
where entity_type <> 'stock_movement'
  and not (entity_type = 'system' and operation in ('restore_snapshot', 'reset_store_data'))
order by store_id, entity_type, entity_id, created_at desc;

-- Restore snapshots are bulk events. Expand them into latest state rows.
insert into entity_snapshots (store_id, entity_type, entity_id, payload, operation, updated_at)
select se.store_id, v.entity_type, item->>'id', item, 'upsert', se.created_at
from sync_events se
cross join lateral (values
  ('product', 'products'),
  ('customer', 'customers'),
  ('sale', 'sales'),
  ('supplier', 'suppliers'),
  ('expense', 'expenses'),
  ('category', 'categories'),
  ('brand', 'brands'),
  ('unit', 'units'),
  ('role', 'roles'),
  ('user', 'users')
) as v(entity_type, collection_name)
cross join lateral jsonb_array_elements(coalesce(se.payload -> v.collection_name, '[]'::jsonb)) item
where se.entity_type = 'system'
  and se.operation = 'restore_snapshot'
  and item ? 'id'
on conflict (store_id, entity_type, entity_id) do update set
  payload = excluded.payload,
  operation = excluded.operation,
  updated_at = excluded.updated_at
where entity_snapshots.updated_at <= excluded.updated_at;

insert into entity_snapshots (store_id, entity_type, entity_id, payload, operation, updated_at)
select se.store_id, 'store_profile', 'store', se.payload->'storeProfile', 'upsert', se.created_at
from sync_events se
where se.entity_type = 'system'
  and se.operation = 'restore_snapshot'
  and se.payload ? 'storeProfile'
on conflict (store_id, entity_type, entity_id) do update set
  payload = excluded.payload,
  operation = excluded.operation,
  updated_at = excluded.updated_at
where entity_snapshots.updated_at <= excluded.updated_at;

-- Apply stock deltas onto product snapshots in event order.
with deltas as (
  select
    store_id,
    payload->>'productId' as product_id,
    sum(coalesce((payload->>'quantity')::numeric, 0)) as qty_delta,
    max(created_at) as last_at
  from sync_events
  where entity_type = 'stock_movement'
    and payload ? 'productId'
  group by store_id, payload->>'productId'
)
update entity_snapshots es
set payload = jsonb_set(es.payload, '{stock}', to_jsonb(greatest(0, coalesce((es.payload->>'stock')::numeric, 0) + d.qty_delta)::int), true)
             || jsonb_build_object('updatedAt', d.last_at),
    updated_at = greatest(es.updated_at, d.last_at)
from deltas d
where es.store_id = d.store_id
  and es.entity_type = 'product'
  and es.entity_id = d.product_id;

commit;
