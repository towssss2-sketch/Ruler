import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import pino from 'pino';
import { PrismaRepository } from '../../prisma.repository';
import { StorageService } from '../document/storage/storage.service';
import { CleanupResult } from '../document/document-cleanup.service';
import { auditIngestionFile } from './ingestion-file-policy';

const logger = pino({ base: undefined });

@Injectable()
export class IngestionFileCleanupService implements OnModuleInit, OnModuleDestroy {
  private timer?: NodeJS.Timeout;
  private running?: Promise<CleanupResult>;
  constructor(private readonly repository: PrismaRepository, private readonly storage: StorageService) {}

  /** 每分钟有限量清理过期上传残留；不清理已接收或已忽略的原件。 */
  onModuleInit(): void {
    this.timer = setInterval((): void => {
      void this.sweep().then((result): void => {
        if (result.failed) logger.warn({ failed: result.failed }, '归集上传临时对象清理待重试');
      });
    }, 60000);
    this.timer.unref();
  }

  /** 等候本实例清理完成再释放连接。 */
  async onModuleDestroy(): Promise<void> {
    if (this.timer) clearInterval(this.timer);
    await this.running;
  }

  /** 同实例去重、多实例数据库锁；失败保留票据，下次有限批次重试。 */
  sweep(): Promise<CleanupResult> {
    if (this.running) return this.running;
    this.running = this.batch().finally((): void => { this.running = undefined; });
    return this.running;
  }

  private async batch(): Promise<CleanupResult> {
    const result = { cleaned: 0, failed: 0 };
    try {
      const tickets = await this.repository.db.ingestionUpload.findMany({ where: { cleanedAt: null,
        expiresAt: { lt: new Date(Date.now() - 60000) } }, orderBy: [{ expiresAt: 'asc' }, { id: 'asc' }], take: 10 });
      for (const ticket of tickets) {
        try { if (await this.clean(ticket.id, ticket.userId)) result.cleaned++; }
        catch { result.failed++; }
      }
    } catch { result.failed++; }
    return result;
  }

  private async clean(id: string, userId: string): Promise<boolean> {
    return this.repository.db.$transaction(async (tx): Promise<boolean> => {
      // 与登记一致：用户→票据；用户已停用仍允许回收自己的未登记残留。
      await tx.$queryRaw`SELECT id FROM "User" WHERE id = ${userId}::uuid FOR UPDATE`;
      await tx.$queryRaw`SELECT id FROM "IngestionUpload" WHERE id = ${id}::uuid FOR UPDATE`;
      const ticket = await tx.ingestionUpload.findUniqueOrThrow({ where: { id } });
      if (ticket.cleanedAt || ticket.expiresAt.getTime() >= Date.now() - 60000) return false;
      await this.storage.delete(ticket.pendingKey);
      const retained = await tx.ingestionFile.findUnique({ where: { storageKey: ticket.storageKey } });
      // 以持久附件记录为准；提交结果不明、归集被忽略/软删，也不删除已接收原件。
      if (!retained) await this.storage.delete(ticket.storageKey);
      await tx.ingestionUpload.update({ where: { id }, data: { cleanedAt: new Date() } });
      await auditIngestionFile(tx, userId, id, 'INGESTION_UPLOAD_CLEANED');
      return true;
    }, { timeout: 60000 });
  }
}
