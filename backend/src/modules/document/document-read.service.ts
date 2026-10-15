import { Injectable } from '@nestjs/common';
import { PrismaRepository } from '../../prisma.repository';
import { BizException } from '../../biz-exception';
import { lockCase } from '../case/case-transaction';
import { DocumentQuery } from './document-input';
import { DocumentView, auditDocument, documentView, storageOperation } from './document-policy';
import { activeDocument } from './document-transaction';
import { StorageService, SignedTransfer } from './storage/storage.service';

export interface DocumentPage { items: DocumentView[]; total: number; page: number; pageSize: number }

@Injectable()
export class DocumentReadService {
  constructor(private readonly repository: PrismaRepository, private readonly storage: StorageService) {}

  /** 锁内再次核验归属，按分类分页；默认只列未删除的当前版本。 */
  async list(userId: string, caseId: string, query: DocumentQuery): Promise<DocumentPage> {
    return this.repository.db.$transaction(async (tx): Promise<DocumentPage> => {
      await lockCase(tx, userId, caseId, false);
      const where = { caseId, deletedAt: null, category: query.category,
        ...(query.includeHistory === 'true' ? {} : { isCurrentVersion: true }) };
      const page = Number(query.page); const pageSize = Number(query.pageSize);
      const total = await tx.document.count({ where });
      const records = await tx.document.findMany({ where, orderBy: [{ uploadedAt: 'desc' }, { id: 'asc' }],
        skip: (page - 1) * pageSize, take: pageSize });
      return { items: records.map(documentView), total, page, pageSize };
    });
  }

  /** 授权后确认对象存在并签发短效下载链接；只审计文档标识，不保存链接。 */
  async download(userId: string, caseId: string, documentId: string): Promise<SignedTransfer> {
    return this.repository.db.$transaction(async (tx): Promise<SignedTransfer> => {
      await lockCase(tx, userId, caseId, false);
      const document = await activeDocument(tx, caseId, documentId);
      if (!await storageOperation(() => this.storage.exists(document.storageKey))) {
        throw new BizException(40909, '文件暂不可用，请联系主办律师核查', 409);
      }
      const signed = await storageOperation(() => this.storage.getDownloadUrl(document.storageKey));
      await auditDocument(tx, userId, caseId, documentId, 'DOCUMENT_DOWNLOAD_SIGNED');
      return signed;
    }, { timeout: 30000 });
  }
}
