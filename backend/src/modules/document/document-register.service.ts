import { Injectable } from '@nestjs/common';
import { DocumentUpload, Prisma } from '@prisma/client';
import { PrismaRepository } from '../../prisma.repository';
import { BizException } from '../../biz-exception';
import { RegisterInput } from './document-input';
import { DocumentView, auditDocument, checkQuota, documentView, storageOperation, verifyObject } from './document-policy';
import { activeDocument, lockDocumentOwner, uploadTicket, validateOrigin } from './document-transaction';
import { StorageService } from './storage/storage.service';

@Injectable()
export class DocumentRegisterService {
  constructor(private readonly repository: PrismaRepository, private readonly storage: StorageService) {}

  /** 锁内核验真实上传并复制到正式键，登记/配额/审计同事务；同票据重试不会重复计费或复制。 */
  async register(userId: string, caseId: string, input: RegisterInput): Promise<DocumentView> {
    return this.repository.db.$transaction(async (tx): Promise<DocumentView> => {
      const owner = await lockDocumentOwner(tx, userId, caseId);
      const ticket = await uploadTicket(tx, userId, caseId, input.uploadId);
      if (ticket.completedAt) return this.completed(tx, ticket, input.category);
      this.requireUnexpired(ticket);
      checkQuota(owner.storageUsedBytes, ticket.sizeBytes, owner.storageQuotaBytes);
      await validateOrigin(tx, userId, caseId, ticket.source, ticket.ingestionId);
      if (ticket.version > 1 && !await tx.document.count({ where: { caseId,
        versionGroupId: ticket.versionGroupId, deletedAt: null } })) {
        throw new BizException(40906, '原文件已删除，请重新申请上传', 409);
      }
      await this.verifyAndCopy(ticket);
      this.requireUnexpired(ticket);
      const current = await this.makeCurrent(tx, ticket);
      const document = await tx.document.create({ data: { id: ticket.documentId, caseId,
        category: input.category, fileName: ticket.fileName, storageKey: ticket.storageKey,
        mimeType: ticket.mimeType, sizeBytes: ticket.sizeBytes, versionGroupId: ticket.versionGroupId,
        version: ticket.version, isCurrentVersion: current, uploadedBy: userId,
        source: ticket.source, ingestionId: ticket.ingestionId } });
      await tx.user.update({ where: { id: owner.id }, data: { storageUsedBytes: { increment: ticket.sizeBytes } } });
      await tx.documentUpload.update({ where: { id: ticket.id }, data: { completedAt: new Date() } });
      await auditDocument(tx, userId, caseId, document.id, 'DOCUMENT_REGISTERED', { version: ticket.version, category: input.category });
      return documentView(document);
    }, { maxWait: 10000, timeout: 60000 });
  }

  private async completed(tx: Prisma.TransactionClient, ticket: DocumentUpload, category: RegisterInput['category']): Promise<DocumentView> {
    const document = await activeDocument(tx, ticket.caseId, ticket.documentId);
    if (document.category !== category) throw new BizException(40907, '该上传已使用其他分类登记', 409);
    return documentView(document);
  }

  private requireUnexpired(ticket: DocumentUpload): void {
    if (ticket.expiresAt <= new Date() || ticket.cleanedAt) throw new BizException(40908, '上传票据已过期，请重新申请', 409);
  }

  private async verifyAndCopy(ticket: DocumentUpload): Promise<void> {
    const source = await storageOperation(() => this.storage.stat(ticket.pendingKey));
    verifyObject(ticket, source);
    await storageOperation(() => this.storage.copy(ticket.pendingKey, ticket.storageKey, source.etag));
    const target = await storageOperation(() => this.storage.stat(ticket.storageKey));
    verifyObject(ticket, target);
    // 不在异常分支立即删正式键：数据库提交结果可能不确定。票据保留，过期回收会先查正式记录。
  }

  private async makeCurrent(tx: Prisma.TransactionClient, ticket: DocumentUpload): Promise<boolean> {
    const where = { caseId: ticket.caseId, versionGroupId: ticket.versionGroupId, deletedAt: null };
    const higher = await tx.document.count({ where: { ...where, version: { gt: ticket.version } } });
    if (higher > 0) return false;
    await tx.document.updateMany({ where: { ...where, isCurrentVersion: true }, data: { isCurrentVersion: false } });
    return true;
  }
}
