import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { PrismaRepository } from '../../prisma.repository';
import { FileUploadInput } from '../document/document-input';
import { reserveUpload } from '../document/upload-reservation';
import { storageOperation } from '../document/document-policy';
import { ingestionStorageKey, sanitizeFileName } from '../document/storage/storage-policy';
import { SignedTransfer, StorageService } from '../document/storage/storage.service';
import { auditIngestionFile, lockIngestionOwner } from './ingestion-file-policy';

export type IngestionOffer = SignedTransfer & { uploadId: string; fileName: string };

@Injectable()
export class IngestionFileUploadService {
  constructor(private readonly repository: PrismaRepository, private readonly storage: StorageService) {}

  /** 无需案件的单文件暂存票据；六类格式/200MiB 上限及签名期限沿用文件模块。 */
  async presign(userId: string, input: FileUploadInput): Promise<IngestionOffer> {
    return storageOperation(async (): Promise<IngestionOffer> => this.repository.db.$transaction(async (tx): Promise<IngestionOffer> => {
      const user = await lockIngestionOwner(tx, userId);
      const fileName = sanitizeFileName(input.fileName);
      await reserveUpload(tx, user, input.sizeBytes);
      const id = randomUUID();
      const pendingKey = ingestionStorageKey(userId, id, randomUUID(), fileName);
      const storageKey = ingestionStorageKey(userId, id, randomUUID(), fileName);
      const signed = await this.storage.getUploadUrl({ key: pendingKey, mimeType: input.mimeType,
        sizeBytes: input.sizeBytes, contentMd5: input.contentMd5 });
      await tx.ingestionUpload.create({ data: { id, userId, fileName, mimeType: input.mimeType,
        sizeBytes: input.sizeBytes, contentMd5: input.contentMd5, pendingKey, storageKey, expiresAt: signed.expiresAt } });
      await auditIngestionFile(tx, userId, id, 'INGESTION_UPLOAD_REQUESTED');
      return { ...signed, uploadId: id, fileName };
    }));
  }
}
