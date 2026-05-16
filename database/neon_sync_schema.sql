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

-- Device-scoped authorization for Host-authoritative sync v2.
-- Keep REQUIRE_DEVICE_TOKEN_AUTH=false until all devices are re-paired.
create table if not exists store_devices (
  store_id text not null,
  branch_id text not null default 'main',
  device_id text not null,
  device_name text default '',
  platform text default '',
  role text default '',
  transport text default '',
  app_version text default '',
  device_token text default '',
  store_epoch integer not null default 1,
  revoked boolean not null default false,
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (store_id, branch_id, device_id)
);

alter table store_devices add column if not exists device_token text default '';
alter table store_devices add column if not exists revoked boolean not null default false;

create index if not exists idx_store_devices_latest
  on store_devices (store_id, branch_id, last_seen_at desc);
