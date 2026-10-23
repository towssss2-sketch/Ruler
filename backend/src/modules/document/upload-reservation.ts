import { Prisma } from '@prisma/client';
import { BizException } from '../../biz-exception';
import { checkQuota } from './document-policy';

/** 在已持有所有者行锁的事务内共同核算案件上传和归集上传，避免跨入口超额。 */
export async function reserveUpload(tx: Prisma.TransactionClient,
  owner: { id: string; storageUsedBytes: bigint; storageQuotaBytes: bigint }, size: number): Promise<void> {
  const remaining = { completedAt: null, expiresAt: { gt: new Date() } };
  const documents = await tx.documentUpload.aggregate({ where: { ownerId: owner.id, ...remaining },
    _sum: { sizeBytes: true }, _count: true });
  const ingestions = await tx.ingestionUpload.aggregate({ where: { userId: owner.id, ...remaining },
    _sum: { sizeBytes: true }, _count: true });
  if (documents._count + ingestions._count >= 20) throw new BizException(42904, '未完成上传过多，请完成或等待票据过期', 429);
  checkQuota(owner.storageUsedBytes + (documents._sum.sizeBytes ?? 0n) + (ingestions._sum.sizeBytes ?? 0n),
    BigInt(size), owner.storageQuotaBytes);
}
