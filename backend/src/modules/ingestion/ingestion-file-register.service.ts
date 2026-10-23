import { ForbiddenException, Injectable } from '@nestjs/common';
import { IngestionUpload, Prisma } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { PrismaRepository } from '../../prisma.repository';
import { EncryptionService } from '../../encryption.service';
import { BizException } from '../../biz-exception';
import { StorageService } from '../document/storage/storage.service';
import { checkQuota, storageOperation, verifyObject } from '../document/document-policy';
import { auditIngestionFile, FileReceipt, fileReceipt, lockIngestionOwner, requireUpload } from './ingestion-file-policy';
import { IngestionViewService } from './ingestion-view.service';

@Injectable()
export class IngestionFileRegisterService {
  constructor(private readonly repository: PrismaRepository, private readonly storage: StorageService,
    private readonly cipher: EncryptionService, private readonly view: IngestionViewService) {}

  /** 验证并冻结副本后计算真实 SHA-256，原子接收、占配额和审计；同票据重试不重复写入。 */
  async register(userId: string, uploadId: string): Promise<FileReceipt> {
    return this.repository.db.$transaction(async (tx): Promise<FileReceipt> => {
      const user = await lockIngestionOwner(tx, userId);
      await tx.$queryRaw`SELECT id FROM "IngestionUpload" WHERE id = ${uploadId}::uuid FOR UPDATE`;
      const ticket = await tx.ingestionUpload.findFirst({ where: { id: uploadId, userId } });
      if (!ticket) throw new ForbiddenException();
      if (ticket.completedAt) return fileReceipt(tx, userId, ticket.ingestionId!, true);
      requireUpload(ticket);
      const hash = await this.freezeAndHash(ticket);
      requireUpload(ticket);
      const contentHash = Buffer.from(this.cipher.blindIndex(hash, `IngestionRecord:${userId}:WECHAT:file:v1`)).toString('hex');
      const existing = await tx.ingestionRecord.findUnique({ where: { userId_channel_contentHash: { userId, channel: 'WECHAT', contentHash } } });
      if (existing?.deletedAt) throw new BizException(40920, '该材料已停用，不能重复导入', 409);
      let id = existing?.id;
      if (!id) {
        checkQuota(user.storageUsedBytes, ticket.sizeBytes, user.storageQuotaBytes);
        id = await this.create(tx, ticket, contentHash);
      }
      await tx.ingestionUpload.update({ where: { id: ticket.id }, data: { ingestionId: id, completedAt: new Date() } });
      if (existing) await auditIngestionFile(tx, userId, ticket.id, 'INGESTION_FILE_DUPLICATE');
      return fileReceipt(tx, userId, id, !!existing);
    }, { maxWait: 10000, timeout: 60000 });
  }

  private async freezeAndHash(ticket: IngestionUpload): Promise<string> {
    return storageOperation(async (): Promise<string> => {
      const source = await this.storage.stat(ticket.pendingKey); verifyObject(ticket, source);
      await this.storage.copy(ticket.pendingKey, ticket.storageKey, source.etag);
      const frozen = await this.storage.stat(ticket.storageKey); verifyObject(ticket, frozen);
      return this.storage.fingerprint(ticket.storageKey, Number(ticket.sizeBytes), frozen.etag);
    });
  }

  private async create(tx: Prisma.TransactionClient, ticket: IngestionUpload, contentHash: string): Promise<string> {
    const id = randomUUID();
    await tx.ingestionRecord.create({ data: { id, userId: ticket.userId, channel: 'WECHAT', contentHash,
      rawContent: this.view.encrypt(`手动导入文件：${ticket.fileName}`, id), attachmentKeys: [ticket.storageKey] } });
    await tx.ingestionFile.create({ data: { ingestionId: id, userId: ticket.userId, fileName: ticket.fileName,
      mimeType: ticket.mimeType, sizeBytes: ticket.sizeBytes, storageKey: ticket.storageKey } });
    await tx.user.update({ where: { id: ticket.userId }, data: { storageUsedBytes: { increment: ticket.sizeBytes } } });
    await auditIngestionFile(tx, ticket.userId, id, 'INGESTION_FILE_RECEIVED');
    return id;
  }
}
