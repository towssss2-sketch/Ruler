import { BadRequestException, HttpException } from '@nestjs/common';
import { Document, DocumentUpload, Prisma } from '@prisma/client';
import { BizException } from '../../biz-exception';
import { StorageError } from './storage/storage-error';
import { StoredObject } from './storage/storage.service';

export type DocumentView = Omit<Document, 'storageKey' | 'sizeBytes' | 'deletedAt'> & { sizeBytes: string };

/** 返回可见元数据；容量用十进制字符串，内部对象键不出接口。 */
export function documentView(record: Document): DocumentView {
  const { storageKey, deletedAt, sizeBytes, ...view } = record;
  void storageKey; void deletedAt;
  return { ...view, sizeBytes: sizeBytes.toString() };
}

/** 存储失败转换为固定消息，不暴露 SDK 错误、签名或对象路径。 */
export async function storageOperation<T>(operation: () => Promise<T>): Promise<T> {
  try { return await operation(); }
  catch (error) {
    if (error instanceof HttpException) throw error;
    if (error instanceof StorageError && error.code === 'INVALID_INPUT') throw new BadRequestException();
    throw new BizException(50304, '文件存储暂不可用，请稍后重试', 503);
  }
}

/** 仅单段直传；真实元数据及协议摘要必须和票据一致，不信任前端登记值。 */
export function verifyObject(ticket: DocumentUpload, object: StoredObject | null): asserts object is StoredObject {
  const digest = Buffer.from(ticket.contentMd5, 'base64').toString('hex');
  if (!object || BigInt(object.sizeBytes) !== ticket.sizeBytes || object.mimeType !== ticket.mimeType
    || object.etag.replaceAll('"', '').toLowerCase() !== digest) {
    throw new BizException(40904, '上传内容尚未就绪或与上传申请不符，请重新上传', 409);
  }
}

/** 配额包含所有保留版本及软删除对象；超额不允许增加容量。 */
export function checkQuota(used: bigint, size: bigint, quota: bigint): void {
  if (used + size > quota) throw new BizException(40304, '主办律师存储配额不足，请先处理容量', 403);
}

/** 文档操作只审计内部标识和经过限制的状态，不记录签名、名称或内容。 */
export async function auditDocument(tx: Prisma.TransactionClient, userId: string, caseId: string,
  documentId: string, action: string, detail: Prisma.InputJsonObject = {}): Promise<void> {
  await tx.auditLog.create({ data: { userId, caseId, resourceId: documentId, resourceType: 'Document', action, detail } });
}
