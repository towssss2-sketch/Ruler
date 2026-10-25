import { ForbiddenException, Injectable } from '@nestjs/common';
import { ApiProperty } from '@nestjs/swagger';
import { IsUUID } from 'class-validator';
import { Document, DocumentCategory, Prisma } from '@prisma/client';
import { PrismaRepository } from '../../prisma.repository';
import { BizException } from '../../biz-exception';
import { lockDocumentOwner } from '../document/document-transaction';
import { auditDocument } from '../document/document-policy';
import { AssignRecord, assignmentRecord } from './ingestion-assign-policy';

export class WithdrawInput {
  @ApiProperty({ format: 'uuid' }) @IsUUID() caseId!: string;
  @ApiProperty({ format: 'uuid', description: '正在撤回的本次归档文档，拒绝旧文档误撤回新归档' }) @IsUUID() documentId!: string;
}
export type ArchiveView = { state: 'UNASSIGNED' | 'UNAVAILABLE' } | {
  state: 'AVAILABLE'; caseId: string; caseNo: string; court: string; documentId: string;
  category: DocumentCategory; canWithdraw: boolean;
};
export interface WithdrawReceipt { withdrawn: true; status: 'PENDING_MATCH' | 'IGNORED' }

@Injectable()
export class IngestionArchiveService {
  constructor(private readonly repository: PrismaRepository) {}

  /** 独立读取当前去向，只返回仍授权的案件摘要；软删或不可访问的案件/文件不泄露旧资料。 */
  async locate(userId: string, id: string): Promise<ArchiveView> {
    return this.repository.db.$transaction(async (tx): Promise<ArchiveView> => {
      const row = await tx.ingestionRecord.findFirst({ where: { id, userId, deletedAt: null } });
      if (!row) throw new ForbiddenException();
      if (!row.matchedCaseId) return { state: 'UNASSIGNED' };
      const target = await tx.case.findFirst({ where: { id: row.matchedCaseId, ownerId: userId, deletedAt: null },
        select: { id: true, caseNo: true, court: true } });
      if (!target) return { state: 'UNAVAILABLE' };
      const documents = await tx.document.findMany({ where: { ingestionId: id, caseId: target.id, deletedAt: null }, take: 2 });
      if (documents.length !== 1) return { state: 'UNAVAILABLE' };
      const document = documents[0]!;
      return { state: 'AVAILABLE', caseId: target.id, caseNo: target.caseNo, court: target.court,
        documentId: document.id, category: document.category,
        canWithdraw: row.status === 'ASSIGNED' && !!await tx.ingestionFile.count({ where: { ingestionId: id } })
          && !await this.otherVersions(tx, document) };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead });
  }

  /** 撤回仅软删指定归档版本并返回待定；原件、历史对象和配额均保留，审计失败全部回滚。 */
  async withdraw(userId: string, id: string, input: WithdrawInput): Promise<WithdrawReceipt> {
    return this.repository.db.$transaction(async (tx): Promise<WithdrawReceipt> => {
      await lockDocumentOwner(tx, userId, input.caseId);
      const row = await assignmentRecord(tx, userId, id);
      const document = row.documents.find((item): boolean => item.id === input.documentId && item.caseId === input.caseId);
      if (!document) throw new ForbiddenException();
      if (await this.repeated(tx, userId, row, document)) {
        return { withdrawn: true, status: row.status as WithdrawReceipt['status'] };
      }
      if (row.status !== 'ASSIGNED' || row.matchedCaseId !== input.caseId || !row.file || document.deletedAt ||
        row.documents.some((item): boolean => item.id !== document.id && !item.deletedAt)) {
        throw new BizException(40926, '归档状态已改变，请刷新核对后操作', 409);
      }
      if (await this.otherVersions(tx, document)) throw new BizException(40927, '文件已有其他保留版本，暂不能撤回', 409);
      if (row.assignmentRevision === 2147483647) throw new BizException(40928, '材料归档次数已达上限', 409);
      await tx.document.update({ where: { id: document.id }, data: { deletedAt: new Date(), isCurrentVersion: false } });
      await tx.ingestionRecord.update({ where: { id }, data: { status: 'PENDING_MATCH', matchedCaseId: null,
        assignmentRevision: { increment: 1 } } });
      await auditDocument(tx, userId, input.caseId, document.id, 'INGESTION_FILE_WITHDRAWN');
      return { withdrawn: true, status: 'PENDING_MATCH' };
    });
  }

  private otherVersions(tx: Prisma.TransactionClient, document: Document): Promise<number> {
    return tx.document.count({ where: { caseId: document.caseId, versionGroupId: document.versionGroupId,
      id: { not: document.id }, deletedAt: null } });
  }

  private async repeated(tx: Prisma.TransactionClient, userId: string, row: AssignRecord, document: Document): Promise<boolean> {
    if (!document.deletedAt || row.matchedCaseId || !['PENDING_MATCH', 'IGNORED'].includes(row.status)) return false;
    return !!await tx.auditLog.count({ where: { userId, caseId: document.caseId, resourceId: document.id,
      resourceType: 'Document', action: 'INGESTION_FILE_WITHDRAWN' } });
  }
}
