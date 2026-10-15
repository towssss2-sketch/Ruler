import { Injectable } from '@nestjs/common';
import { PrismaRepository } from '../../prisma.repository';
import { lockCase } from '../case/case-transaction';
import { DocumentView, auditDocument, documentView } from './document-policy';
import { activeDocument } from './document-transaction';

@Injectable()
export class DocumentWriteService {
  constructor(private readonly repository: PrismaRepository) {}

  /** 更新客户可见标记并同事务审计；该标记不会直接开启尚未上线的客户门户。 */
  async visibility(userId: string, caseId: string, documentId: string, visible: boolean): Promise<DocumentView> {
    return this.repository.db.$transaction(async (tx): Promise<DocumentView> => {
      await lockCase(tx, userId, caseId, true);
      await activeDocument(tx, caseId, documentId);
      const record = await tx.document.update({ where: { id: documentId }, data: { isClientVisible: visible } });
      await auditDocument(tx, userId, caseId, documentId, 'DOCUMENT_VISIBILITY_CHANGED', { isClientVisible: visible });
      return documentView(record);
    });
  }

  /** 仅软删除指定版本；删除当前版时提升最新保留版本。保留对象、配额与审计，不擅自物理销毁。 */
  async remove(userId: string, caseId: string, documentId: string): Promise<{ deleted: true }> {
    return this.repository.db.$transaction(async (tx): Promise<{ deleted: true }> => {
      await lockCase(tx, userId, caseId, true);
      const document = await activeDocument(tx, caseId, documentId);
      await tx.document.update({ where: { id: documentId }, data: { deletedAt: new Date(), isCurrentVersion: false } });
      if (document.isCurrentVersion) {
        const replacement = await tx.document.findFirst({ where: { caseId, versionGroupId: document.versionGroupId,
          deletedAt: null }, orderBy: { version: 'desc' } });
        if (replacement) await tx.document.update({ where: { id: replacement.id }, data: { isCurrentVersion: true } });
      }
      await auditDocument(tx, userId, caseId, documentId, 'DOCUMENT_DELETED');
      return { deleted: true };
    });
  }
}
