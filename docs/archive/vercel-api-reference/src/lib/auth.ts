import jwt from 'jsonwebtoken';
import { prisma } from './prisma';

const secret = process.env.JWT_SECRET;

export type ApiUser = { userId: string; storeId: string; role: string };

export async function requireApiUser(request: Request): Promise<ApiUser> {
  if (!secret) throw new Error('JWT_SECRET is not configured.');
  const header = request.headers.get('authorization') ?? '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (!token) throw new Error('Missing bearer token.');
  const decoded = jwt.verify(token, secret) as Partial<ApiUser>;
  if (!decoded.userId || !decoded.storeId) throw new Error('Invalid bearer token.');

  const member = await prisma.storeMember.findUnique({
    where: { userId_storeId: { userId: decoded.userId, storeId: decoded.storeId } },
  });
  if (!member) throw new Error('User is not a member of this store.');
  return { userId: decoded.userId, storeId: decoded.storeId, role: member.role };
}

export function jsonError(message: string, status = 401) {
  return Response.json({ ok: false, error: message }, { status });
}
