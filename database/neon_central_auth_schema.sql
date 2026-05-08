-- Central Auth schema for Store Manager Pro.
-- Run this in Neon before using cloud-first signup/login.

create table if not exists app_users (
  id text primary key,
  full_name text not null,
  username text unique not null,
  password_hash text not null,
  account_type text not null check (account_type in ('app_admin','merchant','customer','driver')),
  role_id text not null,
  phone text default '',
  email text default '',
  primary_store_id text default '',
  is_active boolean default true,
  is_system boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  last_login_at timestamptz
);

create unique index if not exists idx_app_users_username_unique on app_users (lower(username));

create table if not exists platform_stores (
  id text primary key,
  name text not null,
  owner_user_id text,
  phone text default '',
  address text default '',
  description text default '',
  is_online_enabled boolean default false,
  subscription_plan text default 'trial',
  subscription_status text default 'pending_review',
  commission_rate numeric default 0,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists store_members (
  id text primary key,
  store_id text not null references platform_stores(id) on delete cascade,
  user_id text not null references app_users(id) on delete cascade,
  role text not null check (role in ('owner','manager','cashier','inventory_manager','accountant','orders_staff')),
  permissions jsonb default '[]'::jsonb,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(store_id, user_id)
);

create table if not exists customer_profiles (
  user_id text primary key references app_users(id) on delete cascade,
  default_address text default '',
  phone text default '',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists driver_profiles (
  user_id text primary key references app_users(id) on delete cascade,
  phone text default '',
  zone text default '',
  is_available boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table app_users add column if not exists last_login_at timestamptz;
alter table platform_stores add column if not exists owner_user_id text;
alter table platform_stores add column if not exists is_online_enabled boolean default false;
alter table platform_stores add column if not exists subscription_plan text default 'trial';
alter table platform_stores add column if not exists subscription_status text default 'pending_review';
