import { ForbiddenException, Injectable } from '@nestjs/common';
import { IngestionFile, Prisma } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { BizException } from '../../../biz-exception';
import { PrismaRepository } from '../../../prisma.repository';
import { StorageService } from '../../document/storage/storage.service';
import { MAX_READ_BYTES } from '../../document/storage/object-reader';
import { lockIngestionOwner } from '../ingestion-file-policy';
import { DocumentTextExtractor } from './document-text-extractor';
import { DocumentSuggestion, suggestDocument } from './document-rules';
import { DOCX_MIME, ExtractionResult, manualResult } from './extraction-result';

export interface IngestionPreview { attemptId: string; extraction: ExtractionResult; suggestion: DocumentSuggestion | null }

/** 按需正文预览；原件/归集状态不改写，正文只返回本人，不落明文库或审计。 */
@Injectable()
export class IngestionPreviewService {
  private readonly running = new Set<string>();
  constructor(private readonly repository: PrismaRepository, private readonly storage: StorageService,
    private readonly extractor: DocumentTextExtractor) {}

  /** 实时授权，记录开始/结束，失败可重试；单实例至多两份、每用户一份，无后台隐式排队。 */
  async preview(userId: string, id: string): Promise<IngestionPreview> {
    await this.active(this.repository.db, userId, id);
    if (this.running.has(userId) || this.running.size >= 2) throw new BizException(42920, '正文提取忙，请稍后重试', 429);
    this.running.add(userId);
    try {
      const attemptId = randomUUID();
      const file = await this.audit(userId, id, attemptId);
      const extraction = await this.extract(file);
      const suggestion = extraction.state === 'TEXT' ? suggestDocument(extraction.text) : null;
      await this.audit(userId, id, attemptId, extraction);
      return { attemptId, extraction, suggestion };
    } finally { this.running.delete(userId); }
  }

  private async extract(file: IngestionFile): Promise<ExtractionResult> {
    if (file.mimeType !== 'application/pdf' && file.mimeType !== DOCX_MIME) return manualResult('UNSUPPORTED_FORMAT');
    if (file.sizeBytes > BigInt(MAX_READ_BYTES)) return manualResult('FILE_TOO_LARGE');
    try {
      const metadata = await this.storage.stat(file.storageKey);
      if (!metadata || BigInt(metadata.sizeBytes) !== file.sizeBytes || metadata.mimeType !== file.mimeType) {
        return manualResult('UNAVAILABLE');
      }
      const bytes = await this.storage.read(file.storageKey, metadata.sizeBytes, metadata.etag);
      return await this.extractor.extract(bytes, file.mimeType === 'application/pdf' ? 'pdf' : 'docx');
    } catch { return manualResult('UNAVAILABLE'); }
  }

  private async active(tx: Prisma.TransactionClient, userId: string, id: string): Promise<IngestionFile> {
    const record = await tx.ingestionRecord.findFirst({ where: { id, userId, deletedAt: null }, include: { file: true } });
    if (!record?.file) throw new ForbiddenException();
    return record.file;
  }

  private async audit(userId: string, id: string, attemptId: string, result?: ExtractionResult): Promise<IngestionFile> {
    return this.repository.db.$transaction(async (tx): Promise<IngestionFile> => {
      await lockIngestionOwner(tx, userId);
      await tx.$queryRaw`SELECT id FROM "IngestionRecord" WHERE id = ${id}::uuid FOR SHARE`;
      const file = await this.active(tx, userId, id);
      await tx.auditLog.create({ data: { userId, resourceType: 'IngestionRecord', resourceId: id,
        action: result ? 'INGESTION_PREVIEW_FINISHED' : 'INGESTION_PREVIEW_STARTED',
        detail: { attemptId, ...(result ? { state: result.state,
          ...(result.state === 'MANUAL_REQUIRED' ? { reason: result.reason } : {}) } : {}) } } });
      return file;
    });
  }
}
