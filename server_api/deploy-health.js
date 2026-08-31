import { sql, sendError } from './_db.js';

export default async function handler(req, res) {
  try {
    if (req.method !== 'GET') {
      return res.status(405).json({ ok: false, error: 'Method not allowed' });
    }
    const rows = await sql`select now() as now`;
    return res.status(200).json({
      ok: true,
      service: 'ventio-api',
      databaseTime: rows[0].now,
    });
  } catch (error) {
    sendError(res, error);
  }
}
