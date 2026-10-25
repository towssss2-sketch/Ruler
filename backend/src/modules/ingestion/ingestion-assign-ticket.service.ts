import { Injectable } from '@nestjs/common';
import { DocumentUpload } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { PrismaRepository } from '../../prisma.repository';
import { DocumentView } from '../document/document-policy';
import { lockDocumentOwner } from '../document/document-transaction';
import { reserveUpload } from '../document/upload-reservation';
import { storageKey } from '../document/storage/storage-policy';
import { AssignInput, assignedDocument, assignmentRecord } from './ingestion-assign-policy';

export type AssignmentPreparation = { document: DocumentView } | { ticket: DocumentUpload };

@Injectable()
export class IngestionAssignTicketService {
  constructor(private readonly repository: PrismaRepository) {}

  /** 复制前持久化清理票据；没有上传签名，临时键独立于保留原件，失败副本可由既有回收器处理。 */
  async prepare(userId: string, id: string, input: AssignInput): Promise<AssignmentPreparation> {
    return this.repository.db.$transaction(async (tx): Promise<AssignmentPreparation> => {
      const owner = await lockDocumentOwner(tx, userId, input.caseId);
      const row = await assignmentRecord(tx, userId, id);
      const document = assignedDocument(row, input);
      if (document) return { document };
      const existing = await tx.documentUpload.findFirst({ where: { ingestionId: id, caseId: input.caseId,
        uploadedBy: userId, completedAt: null, cleanedAt: null, expiresAt: { gt: new Date() } }, orderBy: { createdAt: 'desc' } });
      if (existing) return { ticket: existing };
      const file = row.file!;
      await reserveUpload(tx, owner, Number(file.sizeBytes));
      const original = await tx.ingestionUpload.findUniqueOrThrow({ where: { storageKey: file.storageKey } });
      const documentId = randomUUID();
      const ticket = await tx.documentUpload.create({ data: { caseId: input.caseId, ownerId: owner.id,
        uploadedBy: userId, documentId, versionGroupId: randomUUID(), version: 1,
        fileName: file.fileName, mimeType: file.mimeType, sizeBytes: file.sizeBytes, contentMd5: original.contentMd5,
        pendingKey: storageKey(owner.id, input.caseId, randomUUID(), 1, file.fileName),
        storageKey: storageKey(owner.id, input.caseId, documentId, 1, file.fileName),
        source: row.channel, ingestionId: id, expiresAt: new Date(Date.now() + 600000) } });
      await tx.auditLog.create({ data: { userId, caseId: input.caseId, resourceType: 'IngestionRecord', resourceId: id,
        action: 'INGESTION_ASSIGN_REQUESTED', detail: { documentId } } });
      return { ticket };
    });
  }
}
