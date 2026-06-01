import { sql } from '../../_db.js';

export async function ensureHostTransferTables() {
  await sql`
    create table if not exists host_transfer_requests (
      store_id text not null,
      branch_id text not null default 'main',
      requesting_device_id text not null,
      current_host_device_id text default '',
      status text not null default 'pending',
      reason text default '',
      approved_by_host_device_id text default '',
      requested_at timestamptz not null default now(),
      approved_at timestamptz,
      activated_at timestamptz,
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id, requesting_device_id)
    )
  `;
}

export function transferDto(row) {
  return {
    storeId: row.store_id,
    branchId: row.branch_id,
    requestingDeviceId: row.requesting_device_id,
    currentHostDeviceId: row.current_host_device_id || '',
    status: row.status || 'pending',
    reason: row.reason || '',
    approvedByHostDeviceId: row.approved_by_host_device_id || '',
    requestedAt: row.requested_at ? new Date(row.requested_at).toISOString() : '',
    approvedAt: row.approved_at ? new Date(row.approved_at).toISOString() : '',
    activatedAt: row.activated_at ? new Date(row.activated_at).toISOString() : '',
    updatedAt: row.updated_at ? new Date(row.updated_at).toISOString() : '',
  };
}
