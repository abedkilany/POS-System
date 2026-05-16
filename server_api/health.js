import { sql, assertSyncToken, sendError } from './_db.js';

export default async function handler(req, res) {
  try {
    assertSyncToken(req);
    const rows = await sql`select now() as now`;
    res.status(200).json({ ok: true, service: 'pos-sync-api', databaseTime: rows[0].now });
  } catch (error) {
    sendError(res, error);
  }
}
