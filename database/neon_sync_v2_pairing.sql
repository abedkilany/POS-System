-- Ventio Sync V2 pairing/device-auth support.
-- Safe to run repeatedly.

create table if not exists device_pairing_codes (
  code text primary key,
  store_id text not null,
  branch_id text not null default 'main',
  host_device_id text not null,
  host_device_name text default '',
  transport text not null check (transport in ('lan', 'cloud')),
  expires_at timestamptz not null,
  claimed_by_device_id text default '',
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_device_pairing_codes_store
on device_pairing_codes (store_id, branch_id, expires_at desc);

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

create index if not exists idx_store_devices_auth
on store_devices (store_id, branch_id, device_id, role, transport, revoked);
