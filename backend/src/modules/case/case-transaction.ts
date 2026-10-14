import { ForbiddenException } from '@nestjs/common';
import { Prisma } from '@prisma/client';

/** 在事务中锁住父案件并重查所有者，防止守卫检查后被删除或转让。 */
export async function lockCase(tx: Prisma.TransactionClient, userId: string, caseId: string, write: boolean): Promise<void> {
  const rows = await tx.$queryRaw<{ id: string }[]>(Prisma.sql`
    SELECT id FROM "Case" WHERE id = ${caseId}::uuid AND "ownerId" = ${userId}::uuid
    AND "deletedAt" IS NULL ${write ? Prisma.sql`FOR UPDATE` : Prisma.sql`FOR SHARE`}`);
  if (rows.length !== 1) throw new ForbiddenException();
}

/** 每次业务写入在同一事务追加审计；只记录字段名、计数和内部标识。 */
export async function auditCase(tx: Prisma.TransactionClient, userId: string, caseId: string,
  action: string, detail: Prisma.InputJsonObject = {}): Promise<void> {
  await tx.auditLog.create({ data: { userId, caseId, action, resourceType: 'Case', resourceId: caseId, detail } });
}
