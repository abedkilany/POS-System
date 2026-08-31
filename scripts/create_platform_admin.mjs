import crypto from 'crypto';
import { sql } from '../server_api/_db.js';

function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.pbkdf2Sync(String(password), salt, 120000, 32, 'sha256').toString('hex');
  return `pbkdf2_sha256$120000$${salt}$${hash}`;
}

const username = (process.argv[2] || 'admin').trim().toLowerCase();
const password = String(process.argv[3] || '').trim();
const fullName = process.argv.slice(4).join(' ').trim() || 'Ventio Administrator';

if (!password || password.length < 6) {
  console.error('Usage: node scripts/create_platform_admin.mjs admin StrongPassword "Ventio Administrator"');
  process.exit(1);
}

await sql`
  create table if not exists app_accounts (
    id text primary key,
    username text not null,
    namespace_slug text not null default '',
    password_hash text not null,
    full_name text not null default '',
    account_type text not null default 'store_owner',
    status text not null default 'active',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
  )
`;
await sql`alter table app_accounts add column if not exists namespace_slug text not null default ''`;
await sql`alter table app_accounts add column if not exists account_type text not null default 'store_owner'`;
await sql`alter table app_accounts drop constraint if exists app_accounts_username_key`;
await sql`create unique index if not exists app_accounts_username_namespace_key on app_accounts (username, namespace_slug)`;

const id = `acct_${crypto.randomBytes(12).toString('hex')}`;
const passwordHash = hashPassword(password);

const existing = await sql`
  select id from app_accounts
  where username = ${username} and namespace_slug = 'ventio'
  limit 1
`;

if (existing.length) {
  await sql`
    update app_accounts
    set password_hash = ${passwordHash}, full_name = ${fullName}, account_type = 'platform_admin', status = 'active', updated_at = now()
    where username = ${username} and namespace_slug = 'ventio'
  `;
  console.log(`Updated platform admin: ${username}@ventio`);
} else {
  await sql`
    insert into app_accounts (id, username, namespace_slug, password_hash, full_name, account_type, status)
    values (${id}, ${username}, 'ventio', ${passwordHash}, ${fullName}, 'platform_admin', 'active')
  `;
  console.log(`Created platform admin: ${username}@ventio`);
}
