-- POS System Sync Engine v1 schema for Neon PostgreSQL
-- Run this once in Neon SQL Editor.

create table if not exists sync_events (
  id text primary key,
  store_id text not null,
  branch_id text default 'main',
  device_id text default '',
  entity_type text not null,
  entity_id text not null,
  operation text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  received_at timestamptz not null default now()
);

create index if not exists idx_sync_events_store_created
  on sync_events (store_id, branch_id, created_at);

create index if not exists idx_sync_events_entity
  on sync_events (store_id, entity_type, entity_id);

-- Optional: a simple materialized-style latest state table for reporting/debugging.
-- The app sync engine only requires sync_events.
create table if not exists entity_snapshots (
  store_id text not null,
  branch_id text not null default 'main',
  entity_type text not null,
  entity_id text not null,
  payload jsonb not null default '{}'::jsonb,
  operation text not null,
  updated_at timestamptz not null default now(),
  primary key (store_id, branch_id, entity_type, entity_id)
);

-- Host-authoritative sync v2: remote/web clients do not write directly to
-- sync_events. They write proposed changes into this relay inbox. The Host
-- pulls, applies, and republishes accepted changes to sync_events.
create table if not exists cloud_change_requests (
  id text primary key,
  store_id text not null,
  branch_id text default 'main',
  device_id text default '',
  entity_type text not null,
  entity_id text not null,
  operation text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  received_at timestamptz not null default now(),
  status text not null default 'pending',
  accepted_at timestamptz,
  host_device_id text default '',
  last_error text default ''
);

create index if not exists idx_cloud_change_requests_pending
  on cloud_change_requests (store_id, branch_id, status, received_at);


-- Migration safety for databases created before branch-scoped snapshots.
alter table entity_snapshots add column if not exists branch_id text not null default 'main';

-- Accurate Host status for web/online clients.
-- The Windows Host updates this table periodically through /api/sync/host-heartbeat.
-- Web clients must use last_seen_at freshness, not API health, to decide whether the Host is online.
create table if not exists store_host_heartbeats (
  store_id text not null,
  branch_id text not null default 'main',
  host_device_id text not null,
  host_device_name text default '',
  platform text default '',
  app_version text default '',
  sync_mode text default '',
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (store_id, branch_id, host_device_id)
);

create index if not exists idx_store_host_heartbeats_latest
  on store_host_heartbeats (store_id, branch_id, last_seen_at desc);

-- Platform foundation additions: marketplace/admin/customer/order/delivery-ready data.
CREATE TABLE IF NOT EXISTS platform_stores (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  owner_user_id TEXT DEFAULT '',
  phone TEXT DEFAULT '',
  address TEXT DEFAULT '',
  description TEXT DEFAULT '',
  is_online_enabled BOOLEAN DEFAULT FALSE,
  subscription_plan TEXT DEFAULT 'free',
  subscription_status TEXT DEFAULT 'trial',
  commission_rate NUMERIC DEFAULT 0,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS online_orders (
  id TEXT PRIMARY KEY,
  store_id TEXT NOT NULL,
  customer_user_id TEXT DEFAULT '',
  customer_name TEXT DEFAULT '',
  customer_phone TEXT DEFAULT '',
  delivery_address TEXT DEFAULT '',
  notes TEXT DEFAULT '',
  status TEXT DEFAULT 'placed',
  items JSONB DEFAULT '[]'::jsonb,
  delivery_fee NUMERIC DEFAULT 0,
  discount NUMERIC DEFAULT 0,
  payment_method TEXT DEFAULT 'cash_on_delivery',
  payment_status TEXT DEFAULT 'unpaid',
  assigned_driver_user_id TEXT DEFAULT '',
  is_deleted BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_online_orders_store_status ON online_orders(store_id, status);
CREATE INDEX IF NOT EXISTS idx_online_orders_customer ON online_orders(customer_user_id);
CREATE INDEX IF NOT EXISTS idx_online_orders_driver ON online_orders(assigned_driver_user_id);
