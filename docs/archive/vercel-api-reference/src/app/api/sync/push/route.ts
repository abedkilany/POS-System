import { requireApiUser, jsonError } from '@/lib/auth';
import { prisma } from '@/lib/prisma';

export async function POST(request: Request) {
  try {
    const user = await requireApiUser(request);
    const body = await request.json();
    const changes = Array.isArray(body.changes) ? body.changes : [];

    const safeChanges = changes.filter((change: any) =>
      change?.id && change?.storeId === user.storeId && change?.deviceId && change?.entityType && change?.entityId && change?.operation
    );

    await prisma.$transaction(
      safeChanges.map((change: any) =>
        prisma.syncChange.upsert({
          where: { id: String(change.id) },
          update: {},
          create: {
            id: String(change.id),
            storeId: user.storeId,
            branchId: change.branchId ? String(change.branchId) : 'main',
            deviceId: String(change.deviceId),
            entityType: String(change.entityType),
            entityId: String(change.entityId),
            operation: String(change.operation),
            payload: change.payload ?? {},
            createdAt: new Date(change.createdAt ?? Date.now()),
          },
        })
      )
    );

    return Response.json({ ok: true, ackIds: safeChanges.map((change: any) => String(change.id)), serverTime: new Date().toISOString() });
  } catch (error: any) {
    return jsonError(error?.message ?? 'Unauthorized', 401);
  }
}
