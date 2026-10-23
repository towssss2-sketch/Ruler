import { ForbiddenException } from '@nestjs/common';
import { IngestionFile, IngestionUpload, Prisma, User } from '@prisma/client';
import { BizException } from '../../biz-exception';
import { IngestionReceipt } from './ingestion-view.service';

export type IngestionFileView = Pick<IngestionFile, 'id' | 'fileName' | 'mimeType'> & { sizeBytes: string };
export type FileReceipt = IngestionReceipt & { file: IngestionFileView };

/** 用户级上传与现有归集写入使用同一用户行锁，禁止停用账号操作。 */
export async function lockIngestionOwner(tx: Prisma.TransactionClient, userId: string): Promise<User> {
  await tx.$queryRaw`SELECT id FROM "User" WHERE id = ${userId}::uuid FOR UPDATE`;
  const user = await tx.user.findFirst({ where: { id: userId, deletedAt: null } });
  if (!user) throw new ForbiddenException();
  return user;
}

/** 文件完成/下载前实时限制归集记录归属，忽略不删除原附件。 */
export async function fileReceipt(tx: Prisma.TransactionClient, userId: string, id: string, duplicate: boolean): Promise<FileReceipt> {
  const row = await tx.ingestionRecord.findFirst({ where: { id, userId, deletedAt: null }, include: { file: true } });
  if (!row?.file) throw new ForbiddenException();
  return { id, status: row.status, duplicate, file: fileView(row.file) };
}

/** 最小文件元数据不返回用户、指纹、内部键和签名。 */
export function fileView(file: IngestionFile): IngestionFileView {
  return { id: file.id, fileName: file.fileName, mimeType: file.mimeType, sizeBytes: file.sizeBytes.toString() };
}

/** 上传票据只能在有效期内登记，过期不自动延长签名。 */
export function requireUpload(ticket: IngestionUpload): void {
  if (ticket.expiresAt <= new Date() || ticket.cleanedAt) throw new BizException(40908, '上传票据已过期，请重新申请', 409);
}

/** 写操作同事务审计，不记录文件名、内容或存储键。 */
export async function auditIngestionFile(tx: Prisma.TransactionClient, userId: string, id: string, action: string): Promise<void> {
  await tx.auditLog.create({ data: { userId, resourceType: 'IngestionFile', resourceId: id, action, detail: {} } });
}
