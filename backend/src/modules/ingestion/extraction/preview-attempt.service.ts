import { ForbiddenException, Injectable } from '@nestjs/common';
import { IngestionFile, IngestionPreviewAttempt, Prisma } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { BizException } from '../../../biz-exception';
import { PrismaRepository } from '../../../prisma.repository';
import { PageInput } from '../../case/case-input';
import { lockIngestionOwner } from '../ingestion-file-policy';
import { ExtractionResult } from './extraction-result';
import { PreviewAttemptPage, previewAttemptView } from './preview-attempt-view';

/** 原件提取尝试独立于归档状态；数据库租期避免重启后永久卡住及迟到覆写。 */
@Injectable()
export class PreviewAttemptService {
  constructor(private readonly repository: PrismaRepository) {}

  /** 短事务原子取得用户解析槽位；过期失败保留，正文不入库。 */
  async begin(userId: string, id: string): Promise<{ attemptId: string; file: IngestionFile }> {
    return this.repository.db.$transaction(async (tx) => {
      await lockIngestionOwner(tx, userId);
      const file = await this.active(tx, userId, id);
      const now = await this.now(tx);
      const running = await tx.ingestionPreviewAttempt.findFirst({ where: { userId, status: 'RUNNING' } });
      if (running) {
        if (running.leaseExpiresAt > now) throw new BizException(42920, '正文提取忙，请稍后查看处理记录', 429);
        await this.interrupt(tx, running);
      }
      const attemptId = randomUUID();
      await tx.ingestionPreviewAttempt.create({ data: { id: attemptId, ingestionId: id, userId,
        startedAt: now, leaseExpiresAt: new Date(now.getTime() + 120000) } });
      await this.audit(tx, userId, id, attemptId, 'INGESTION_PREVIEW_STARTED', {});
      return { attemptId, file };
    });
  }

  /** 只有本次未过期尝试可完成；提交失败不返回正文，迟到完成不会覆盖新的尝试。 */
  async finish(userId: string, id: string, attemptId: string, result: ExtractionResult): Promise<void> {
    const accepted = await this.repository.db.$transaction(async (tx): Promise<boolean | 'DENIED'> => {
      await lockIngestionOwner(tx, userId);
      const row = await tx.ingestionPreviewAttempt.findFirst({ where: { id: attemptId, ingestionId: id, userId } });
      if (!row) throw new ForbiddenException();
      try { await this.active(tx, userId, id); }
      catch (error) {
        if (!(error instanceof ForbiddenException)) throw error;
        if (row.status === 'RUNNING') await this.abandon(tx, row);
        return 'DENIED';
      }
      if (row.status !== 'RUNNING') return false;
      const now = await this.now(tx);
      if (row.leaseExpiresAt <= now) { await this.interrupt(tx, row); return false; }
      const reason = result.state === 'MANUAL_REQUIRED' ? result.reason : null;
      await tx.ingestionPreviewAttempt.update({ where: { id: attemptId }, data: {
        status: result.state === 'TEXT' ? 'SUCCEEDED' : 'MANUAL_REQUIRED', reason, finishedAt: now } });
      await this.audit(tx, userId, id, attemptId, 'INGESTION_PREVIEW_FINISHED',
        { state: result.state, ...(reason ? { reason } : {}) });
      return true;
    });
    if (accepted === 'DENIED') throw new ForbiddenException();
    if (!accepted) throw new BizException(40920, '本次提取已中断，请查看处理记录后重新提取', 409);
  }

  /** 只读有界分页，同一快照计数；实时授权，不返回正文、对象键或租期内部字段。 */
  async history(userId: string, id: string, query: PageInput): Promise<PreviewAttemptPage> {
    return this.repository.db.$transaction(async (tx) => {
      await this.active(tx, userId, id);
      const now = await this.now(tx), where = { ingestionId: id, userId };
      const page = Number(query.page), pageSize = Number(query.pageSize);
      const total = await tx.ingestionPreviewAttempt.count({ where });
      const rows = await tx.ingestionPreviewAttempt.findMany({ where, skip: (page - 1) * pageSize, take: pageSize,
        orderBy: [{ startedAt: 'desc' }, { id: 'desc' }] });
      return { items: rows.map((row) => previewAttemptView(row, now)), total, page, pageSize };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead });
  }

  /** 读取/提交时核对原件归属；软删除与账号停用后拒绝。 */
  async active(tx: Prisma.TransactionClient, userId: string, id: string): Promise<IngestionFile> {
    await tx.$queryRaw`SELECT id FROM "IngestionRecord" WHERE id = ${id}::uuid FOR SHARE`;
    const row = await tx.ingestionRecord.findFirst({ where: { id, userId, deletedAt: null, user: { deletedAt: null } }, include: { file: true } });
    if (!row?.file) throw new ForbiddenException();
    return row.file;
  }

  private async now(tx: Prisma.TransactionClient): Promise<Date> {
    const rows = await tx.$queryRaw<Array<{ now: Date }>>`SELECT clock_timestamp()::timestamptz(3) AS now`;
    return rows[0]!.now;
  }

  private async interrupt(tx: Prisma.TransactionClient, row: IngestionPreviewAttempt): Promise<void> {
    await tx.ingestionPreviewAttempt.update({ where: { id: row.id }, data: { status: 'INTERRUPTED', finishedAt: row.leaseExpiresAt } });
    await this.audit(tx, row.userId, row.ingestionId, row.id, 'INGESTION_PREVIEW_INTERRUPTED', {});
  }

  private async abandon(tx: Prisma.TransactionClient, row: IngestionPreviewAttempt): Promise<void> {
    const now = await this.now(tx);
    if (row.leaseExpiresAt <= now) return this.interrupt(tx, row);
    await tx.ingestionPreviewAttempt.update({ where: { id: row.id }, data: {
      status: 'MANUAL_REQUIRED', reason: 'UNAVAILABLE', finishedAt: now } });
    await this.audit(tx, row.userId, row.ingestionId, row.id, 'INGESTION_PREVIEW_ABORTED', {});
  }

  private async audit(tx: Prisma.TransactionClient, userId: string, id: string, attemptId: string,
    action: string, detail: Prisma.InputJsonObject): Promise<void> {
    await tx.auditLog.create({ data: { userId, resourceType: 'IngestionRecord', resourceId: id, action, detail: { attemptId, ...detail } } });
  }
}
