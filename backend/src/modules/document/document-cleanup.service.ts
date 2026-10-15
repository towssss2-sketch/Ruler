import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import pino from 'pino';
import { PrismaRepository } from '../../prisma.repository';
import { StorageService } from './storage/storage.service';
import { auditDocument } from './document-policy';

const logger = pino({ base: undefined });
export interface CleanupResult { cleaned: number; failed: number }

@Injectable()
export class DocumentCleanupService implements OnModuleInit, OnModuleDestroy {
  private timer?: NodeJS.Timeout;
  private running?: Promise<CleanupResult>;
  constructor(private readonly repository: PrismaRepository, private readonly storage: StorageService) {}

  /** 每分钟有限量回收过期票据；多实例以数据库锁协调，不影响仍有效的直传链接。 */
  onModuleInit(): void {
    this.timer = setInterval((): void => {
      void this.sweep().then((result): void => {
        if (result.failed) logger.warn({ failed: result.failed }, '上传临时对象清理待重试');
      });
    }, 60000);
    this.timer.unref();
  }

  /** 应用关闭时停止定时器并等候自己的清理完成，避免关闭连接后继续使用。 */
  async onModuleDestroy(): Promise<void> {
    if (this.timer) clearInterval(this.timer);
    await this.running;
  }

  /** 执行一批可重试清理；失败只返回计数，不输出底层错误或对象键。 */
  sweep(): Promise<CleanupResult> {
    if (this.running) return this.running;
    this.running = this.batch().finally((): void => { this.running = undefined; });
    return this.running;
  }

  private async batch(): Promise<CleanupResult> {
    const result = { cleaned: 0, failed: 0 };
    try {
      const tickets = await this.repository.db.documentUpload.findMany({ where: { cleanedAt: null,
        expiresAt: { lt: new Date(Date.now() - 60000) } }, orderBy: [{ expiresAt: 'asc' }, { id: 'asc' }], take: 10 });
      for (const ticket of tickets) {
        try { if (await this.clean(ticket.id, ticket.caseId)) result.cleaned++; }
        catch { result.failed++; }
      }
    } catch { result.failed++; }
    return result;
  }

  private async clean(id: string, caseId: string): Promise<boolean> {
    return this.repository.db.$transaction(async (tx): Promise<boolean> => {
      // 与登记相同的父案件→票据顺序；案件已软删除时仍能回收未登记对象。
      await tx.$queryRaw`SELECT id FROM "Case" WHERE id = ${caseId}::uuid FOR UPDATE`;
      await tx.$queryRaw`SELECT id FROM "DocumentUpload" WHERE id = ${id}::uuid FOR UPDATE`;
      const ticket = await tx.documentUpload.findUniqueOrThrow({ where: { id } });
      if (ticket.cleanedAt || ticket.expiresAt.getTime() >= Date.now() - 60000) return false;
      await this.storage.delete(ticket.pendingKey);
      // 即使事务提交曾返回网络错误，也绝不删除已登记（包括软删除）的正式对象。
      const registered = await tx.document.findUnique({ where: { id: ticket.documentId }, select: { id: true } });
      if (!registered) {
        await this.storage.delete(ticket.storageKey);
      }
      await tx.documentUpload.update({ where: { id }, data: { cleanedAt: new Date() } });
      await auditDocument(tx, ticket.uploadedBy, caseId, ticket.documentId, 'DOCUMENT_UPLOAD_CLEANED', { retainedDocument: !!registered });
      return true;
    }, { timeout: 60000 });
  }
}
