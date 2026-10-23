import { ForbiddenException, Injectable } from '@nestjs/common';
import { PrismaRepository } from '../../prisma.repository';
import { StorageService, SignedTransfer } from '../document/storage/storage.service';
import { storageOperation } from '../document/document-policy';
import { fileReceipt, IngestionFileView, lockIngestionOwner } from './ingestion-file-policy';

@Injectable()
export class IngestionFileReadService {
  constructor(private readonly repository: PrismaRepository, private readonly storage: StorageService) {}

  /** 只返回本人有效归集附件的可见元数据，不泄露对象键。 */
  async metadata(userId: string, id: string): Promise<IngestionFileView> {
    return (await fileReceipt(this.repository.db, userId, id, false)).file;
  }

  /** 实时授权后签发短效下载；忽略保留可下载原件，删除记录则拒绝。 */
  async download(userId: string, id: string): Promise<SignedTransfer> {
    return this.repository.db.$transaction(async (tx): Promise<SignedTransfer> => {
      await lockIngestionOwner(tx, userId);
      await tx.$queryRaw`SELECT id FROM "IngestionRecord" WHERE id = ${id}::uuid FOR SHARE`;
      await fileReceipt(tx, userId, id, false);
      const file = await tx.ingestionFile.findUniqueOrThrow({ where: { ingestionId: id } });
      return storageOperation(async (): Promise<SignedTransfer> => {
        if (!await this.storage.exists(file.storageKey)) throw new ForbiddenException();
        return this.storage.getDownloadUrl(file.storageKey);
      });
    });
  }
}
