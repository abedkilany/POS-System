-- Ventio Sync Engine v1 schema for Neon PostgreSQL
-- Run this once in Neon SQL Editor.

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
  suspended boolean not null default false,
  wipe_pending boolean not null default false,
  wipe_requested_at timestamptz,
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (store_id, branch_id, device_id)
);

alter table store_devices add column if not exists device_token text default '';
alter table store_devices add column if not exists revoked boolean not null default false;
alter table store_devices add column if not exists suspended boolean not null default false;
alter table store_devices add column if not exists wipe_pending boolean not null default false;
alter table store_devices add column if not exists wipe_requested_at timestamptz;
alter table store_devices add column if not exists active_transport text default '';
alter table store_devices add column if not exists last_sync_transport text default '';
alter table store_devices add column if not exists last_applied_cursor timestamptz;
alter table store_devices add column if not exists last_ack_cursor timestamptz;
alter table store_devices add column if not exists last_applied_sequence bigint not null default 0;
alter table store_devices add column if not exists last_ack_sequence bigint not null default 0;
alter table store_devices add column if not exists last_ack_at timestamptz;
alter table store_devices add column if not exists online boolean not null default false;
alter table store_devices add column if not exists device_public_key text default '';

create index if not exists idx_store_devices_latest
  on store_devices (store_id, branch_id, last_seen_at desc);

-- Direct pairing and signaling use store_devices; no legacy transport tables are created here.
