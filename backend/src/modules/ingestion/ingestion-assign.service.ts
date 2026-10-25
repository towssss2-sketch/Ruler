import { Injectable } from '@nestjs/common';
import { DocumentUpload } from '@prisma/client';
import { PrismaRepository } from '../../prisma.repository';
import { BizException } from '../../biz-exception';
import { DocumentView, auditDocument, checkQuota, documentView, storageOperation, verifyObject } from '../document/document-policy';
import { lockDocumentOwner, uploadTicket } from '../document/document-transaction';
import { StorageService } from '../document/storage/storage.service';
import { AssignInput, assignedDocument, assignmentRecord } from './ingestion-assign-policy';
import { IngestionAssignTicketService } from './ingestion-assign-ticket.service';

@Injectable()
export class IngestionAssignService {
  constructor(private readonly repository: PrismaRepository, private readonly storage: StorageService,
    private readonly tickets: IngestionAssignTicketService) {}

  /** 人工选择案件及分类后归档。保留原件并计新增副本容量，状态、文档、容量及审计同事务提交。 */
  async assign(userId: string, id: string, input: AssignInput): Promise<DocumentView> {
    const preparation = await this.tickets.prepare(userId, id, input);
    if ('document' in preparation) return preparation.document;
    return this.repository.db.$transaction(async (tx): Promise<DocumentView> => {
      const owner = await lockDocumentOwner(tx, userId, input.caseId);
      const row = await assignmentRecord(tx, userId, id);
      const existing = assignedDocument(row, input);
      if (existing) return existing;
      const ticket = await uploadTicket(tx, userId, input.caseId, preparation.ticket.id);
      this.requireActive(ticket);
      checkQuota(owner.storageUsedBytes, ticket.sizeBytes, owner.storageQuotaBytes);
      await this.copy(row.file!.storageKey, ticket);
      this.requireActive(ticket);
      await tx.ingestionRecord.update({ where: { id }, data: { status: 'ASSIGNED', matchedCaseId: input.caseId, stage: 'MATCH' } });
      const document = await tx.document.create({ data: { id: ticket.documentId, caseId: input.caseId,
        category: input.category, fileName: ticket.fileName, storageKey: ticket.storageKey,
        mimeType: ticket.mimeType, sizeBytes: ticket.sizeBytes, versionGroupId: ticket.versionGroupId,
        version: 1, uploadedBy: userId, source: row.channel, ingestionId: id } });
      await tx.user.update({ where: { id: owner.id }, data: { storageUsedBytes: { increment: ticket.sizeBytes } } });
      await tx.documentUpload.update({ where: { id: ticket.id }, data: { completedAt: new Date() } });
      await auditDocument(tx, userId, input.caseId, document.id, 'INGESTION_FILE_ASSIGNED', { category: input.category });
      return documentView(document);
    }, { maxWait: 10000, timeout: 60000 });
  }

  private requireActive(ticket: DocumentUpload): void {
    if (ticket.completedAt || ticket.cleanedAt || ticket.expiresAt <= new Date()) {
      throw new BizException(40924, '归档准备已过期，请重新提交', 409);
    }
  }

  private async copy(sourceKey: string, ticket: DocumentUpload): Promise<void> {
    const source = await storageOperation(() => this.storage.stat(sourceKey));
    verifyObject(ticket, source);
    await storageOperation(() => this.storage.copy(sourceKey, ticket.storageKey, source.etag));
    verifyObject(ticket, await storageOperation(() => this.storage.stat(ticket.storageKey)));
    // 失败不立即删除：提交结果可能未知，持久票据回收器会先检查正式文档是否存在。
  }
}
