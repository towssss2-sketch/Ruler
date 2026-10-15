import { ForbiddenException } from '@nestjs/common';
import { Document, DocumentUpload, Prisma, User } from '@prisma/client';
import { BizException } from '../../biz-exception';
import { lockCase } from '../case/case-transaction';

/** 统一先锁案件、再锁所有者；同一所有者不同案件的上传也串行核算容量。 */
export async function lockDocumentOwner(tx: Prisma.TransactionClient, userId: string, caseId: string): Promise<User> {
  await lockCase(tx, userId, caseId, true);
  const record = await tx.case.findUniqueOrThrow({ where: { id: caseId } });
  await tx.$queryRaw`SELECT id FROM "User" WHERE id = ${record.ownerId}::uuid FOR UPDATE`;
  const owner = await tx.user.findFirst({ where: { id: record.ownerId, deletedAt: null } });
  if (!owner) throw new ForbiddenException();
  return owner;
}

/** 锁内再验证票据的案件和操作者；失败不披露他人票据状态。 */
export async function uploadTicket(tx: Prisma.TransactionClient, userId: string, caseId: string,
  uploadId: string): Promise<DocumentUpload> {
  await tx.$queryRaw`SELECT id FROM "DocumentUpload" WHERE id = ${uploadId}::uuid FOR UPDATE`;
  const ticket = await tx.documentUpload.findFirst({ where: { id: uploadId, caseId, uploadedBy: userId } });
  if (!ticket) throw new ForbiddenException();
  return ticket;
}

/** 事务内重新读取活跃文档，守卫通过后删除的文件仍不能被操作。 */
export async function activeDocument(tx: Prisma.TransactionClient, caseId: string, id: string): Promise<Document> {
  const record = await tx.document.findFirst({ where: { id, caseId, deletedAt: null } });
  if (!record) throw new ForbiddenException();
  return record;
}

/** 归集来源仅供内部管道；必须属于同一用户、同一案件及渠道，不能伪造来源。 */
export async function validateOrigin(tx: Prisma.TransactionClient, userId: string, caseId: string,
  source: DocumentUpload['source'], ingestionId: string | null): Promise<void> {
  if (source === 'MANUAL' && ingestionId === null) return;
  if (source === 'MANUAL' || !ingestionId) throw new ForbiddenException();
  const ingestion = await tx.ingestionRecord.findFirst({ where: { id: ingestionId, userId, matchedCaseId: caseId,
    channel: source, deletedAt: null, status: { in: ['MATCHED', 'ASSIGNED'] } } });
  if (!ingestion) throw new BizException(40305, '无权使用该归集来源', 403);
}
