import { requireApiUser, jsonError } from '@/lib/auth';
import { prisma } from '@/lib/prisma';

export async function GET(request: Request) {
  try {
    const user = await requireApiUser(request);
    const url = new URL(request.url);
    const since = url.searchParams.get('since');
    const createdAt = since ? { gt: new Date(since) } : undefined;

    const changes = await prisma.syncChange.findMany({
      where: { storeId: user.storeId, ...(createdAt ? { createdAt } : {}) },
      orderBy: { createdAt: 'asc' },
      take: 1000,
    });

    return Response.json({
      ok: true,
      generatedAt: new Date().toISOString(),
      changes: changes.map((change) => ({
        id: change.id,
        storeId: change.storeId,
        branchId: change.branchId,
        deviceId: change.deviceId,
        entityType: change.entityType,
        entityId: change.entityId,
        operation: change.operation,
        payload: change.payload,
        createdAt: change.createdAt.toISOString(),
        isSynced: true,
      })),
    });
  } catch (error: any) {
    return jsonError(error?.message ?? 'Unauthorized', 401);
  }
}
