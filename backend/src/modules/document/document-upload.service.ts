import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { DocumentUpload, Prisma } from '@prisma/client';
import { PrismaRepository } from '../../prisma.repository';
import { BizException } from '../../biz-exception';
import { PresignInput } from './document-input';
import { auditDocument, checkQuota, storageOperation } from './document-policy';
import { activeDocument, lockDocumentOwner, validateOrigin } from './document-transaction';
import { StorageService, SignedTransfer } from './storage/storage.service';
import { sanitizeFileName, storageKey, uploadHeaders } from './storage/storage-policy';

export interface UploadOffer extends SignedTransfer { uploadId: string; fileName: string; version: number }
export interface UploadOrigin { source: DocumentUpload['source']; ingestionId: string | null }

@Injectable()
export class DocumentUploadService {
  constructor(private readonly repository: PrismaRepository, private readonly storage: StorageService) {}

  /** 签发绑定操作者的上传票据；预留容量，拒绝超额/危险名称/过多未完成申请。内部管道可指定核验来源。 */
  async presign(userId: string, caseId: string, input: PresignInput,
    origin: UploadOrigin = { source: 'MANUAL', ingestionId: null }): Promise<UploadOffer> {
    return storageOperation(async (): Promise<UploadOffer> => {
      const fileName = sanitizeFileName(input.fileName);
      return this.repository.db.$transaction(async (tx): Promise<UploadOffer> => {
        const owner = await lockDocumentOwner(tx, userId, caseId);
        await validateOrigin(tx, userId, caseId, origin.source, origin.ingestionId);
        await this.reserveQuota(tx, owner, input.sizeBytes);
        const series = await this.nextVersion(tx, caseId, input.previousDocumentId);
        const documentId = randomUUID();
        const pendingKey = storageKey(owner.id, caseId, randomUUID(), 1, fileName);
        const finalKey = storageKey(owner.id, caseId, documentId, series.version, fileName);
        const request = { key: pendingKey, mimeType: input.mimeType, sizeBytes: input.sizeBytes, contentMd5: input.contentMd5 };
        uploadHeaders(request);
        const signed = await this.storage.getUploadUrl(request);
        const ticket = await tx.documentUpload.create({ data: { caseId, ownerId: owner.id, uploadedBy: userId,
          documentId, ...series, fileName, mimeType: input.mimeType, sizeBytes: input.sizeBytes,
          contentMd5: input.contentMd5, pendingKey, storageKey: finalKey, expiresAt: signed.expiresAt, ...origin } });
        await auditDocument(tx, userId, caseId, documentId, 'DOCUMENT_UPLOAD_REQUESTED', { uploadId: ticket.id });
        return { ...signed, uploadId: ticket.id, fileName, version: series.version };
      });
    });
  }

  private async reserveQuota(tx: Prisma.TransactionClient, owner: { id: string; storageUsedBytes: bigint; storageQuotaBytes: bigint },
    size: number): Promise<void> {
    const pending = await tx.documentUpload.aggregate({ where: { ownerId: owner.id, completedAt: null,
      expiresAt: { gt: new Date() } }, _sum: { sizeBytes: true }, _count: true });
    if (pending._count >= 20) throw new BizException(42904, '未完成上传过多，请完成或等待票据过期', 429);
    checkQuota(owner.storageUsedBytes + (pending._sum.sizeBytes ?? 0n), BigInt(size), owner.storageQuotaBytes);
  }

  private async nextVersion(tx: Prisma.TransactionClient, caseId: string, previousId?: string): Promise<{ versionGroupId: string; version: number }> {
    if (!previousId) return { versionGroupId: randomUUID(), version: 1 };
    const previous = await activeDocument(tx, caseId, previousId);
    const where = { caseId, versionGroupId: previous.versionGroupId };
    const documents = await tx.document.aggregate({ where, _max: { version: true } });
    const uploads = await tx.documentUpload.aggregate({ where, _max: { version: true } });
    const version = Math.max(documents._max.version ?? 0, uploads._max.version ?? 0) + 1;
    if (version > 2147483647) throw new BizException(40905, '文件版本已达上限', 409);
    return { versionGroupId: previous.versionGroupId, version };
  }
}
