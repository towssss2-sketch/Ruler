import { ForbiddenException, Injectable } from '@nestjs/common';
import { IngestionRecord, IngestionFile, Prisma } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { BizException } from '../../biz-exception';
import { PrismaRepository } from '../../prisma.repository';
import { PageInput } from '../case/case-input';
import { IngestionDetail, IngestionPage, IngestionReceipt, IngestionViewService } from './ingestion-view.service';

@Injectable()
export class IngestionService {
  constructor(private readonly repository: PrismaRepository, private readonly view: IngestionViewService) {}

  /** 事务接收文字与审计；同用户同渠道正文重复时返回原状态，不自动恢复已忽略记录。 */
  async receive(userId: string, text: string): Promise<IngestionReceipt> {
    const contentHash = this.view.hash(text, userId);
    return this.repository.db.$transaction(async (tx): Promise<IngestionReceipt> => {
      await this.lockUser(tx, userId);
      const existing = await tx.ingestionRecord.findUnique({ where: { userId_channel_contentHash: {
        userId, channel: 'WECHAT', contentHash } } });
      if (existing) {
        if (existing.deletedAt) throw new BizException(40920, '该材料已停用，不能重复导入', 409);
        return { id: existing.id, status: existing.status, duplicate: true };
      }
      const id = randomUUID();
      const record = await tx.ingestionRecord.create({ data: { id, userId, channel: 'WECHAT', contentHash,
        rawContent: this.view.encrypt(text, id) } });
      await this.audit(tx, userId, id, 'INGESTION_RECEIVED');
      return { id, status: record.status, duplicate: false };
    });
  }

  /** 每次查询限定当前用户及未删除记录；同一快照计数/分页，不接受外部 owner 条件。 */
  async list(userId: string, query: PageInput, pending: boolean): Promise<IngestionPage> {
    const page = Number(query.page); const pageSize = Number(query.pageSize);
    return this.repository.db.$transaction(async (tx): Promise<IngestionPage> => {
      const where: Prisma.IngestionRecordWhereInput = { userId, deletedAt: null,
        ...(pending ? { status: 'PENDING_MATCH' } : {}) };
      const total = await tx.ingestionRecord.count({ where });
      const records = await tx.ingestionRecord.findMany({ where, take: pageSize, skip: (page - 1) * pageSize,
        orderBy: [{ receivedAt: 'desc' }, { id: 'desc' }], include: { file: true } });
      return { items: records.map((record): IngestionSummaryResult => this.view.summary(record)), total, page, pageSize };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead });
  }

  /** 详情按记录归属授权；不存在、删除和他人记录均为相同拒绝响应。 */
  async detail(userId: string, id: string): Promise<IngestionDetail> {
    const record = await this.active(this.repository.db, userId, id);
    return this.view.detail(record);
  }

  /** 忽略仅作用于待定记录，保留密文和历史；幂等重试不重复写审计。 */
  async ignore(userId: string, id: string): Promise<{ ignored: true }> {
    return this.repository.db.$transaction(async (tx): Promise<{ ignored: true }> => {
      await this.lockUser(tx, userId);
      await tx.$queryRaw`SELECT id FROM "IngestionRecord" WHERE id = ${id}::uuid AND "userId" = ${userId}::uuid FOR UPDATE`;
      const record = await this.active(tx, userId, id);
      if (record.status === 'IGNORED') return { ignored: true };
      if (record.status !== 'PENDING_MATCH' || record.matchedCaseId ||
        await tx.document.count({ where: { ingestionId: id, deletedAt: null } })) {
        throw new BizException(40921, '材料已关联案件，不能从待定区忽略', 409);
      }
      await tx.ingestionRecord.update({ where: { id }, data: { status: 'IGNORED' } });
      await this.audit(tx, userId, id, 'INGESTION_IGNORED');
      return { ignored: true };
    });
  }

  private async active(tx: Prisma.TransactionClient, userId: string, id: string): Promise<IngestionRecord & { file: IngestionFile | null }> {
    const record = await tx.ingestionRecord.findFirst({ where: { id, userId, deletedAt: null }, include: { file: true } });
    if (!record) throw new ForbiddenException();
    return record;
  }

  private async lockUser(tx: Prisma.TransactionClient, userId: string): Promise<void> {
    const rows = await tx.$queryRaw<{ id: string }[]>`SELECT id FROM "User" WHERE id = ${userId}::uuid AND "deletedAt" IS NULL FOR UPDATE`;
    if (rows.length !== 1) throw new ForbiddenException();
  }

  private async audit(tx: Prisma.TransactionClient, userId: string, id: string, action: string): Promise<void> {
    await tx.auditLog.create({ data: { userId, action, resourceType: 'IngestionRecord', resourceId: id, detail: {} } });
  }
}

type IngestionSummaryResult = IngestionPage['items'][number];
