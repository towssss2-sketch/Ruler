import { Injectable } from '@nestjs/common';
import { IngestionRecord } from '@prisma/client';
import { EncryptionService } from '../../encryption.service';

export type IngestionSummary = Pick<IngestionRecord, 'id' | 'channel' | 'status' | 'receivedAt'> & { preview: string };
export type IngestionDetail = IngestionSummary & { rawContent: string };
export interface IngestionReceipt { id: string; status: IngestionRecord['status']; duplicate: boolean }
export interface IngestionPage { items: IngestionSummary[]; total: number; page: number; pageSize: number }

@Injectable()
export class IngestionViewService {
  constructor(private readonly cipher: EncryptionService) {}

  /** 授权查询后解密；原文只在详情返回，列表仅返回最多 200 个 Unicode 码点。 */
  summary(record: IngestionRecord): IngestionSummary {
    return { id: record.id, channel: record.channel, status: record.status, receivedAt: record.receivedAt,
      preview: Array.from(this.decrypt(record)).slice(0, 200).join('') };
  }

  /** 返回原文但不返回密文、哈希、对象键、链接字段、AI 结构或其他用户信息。 */
  detail(record: IngestionRecord): IngestionDetail {
    return { ...this.summary(record), rawContent: this.decrypt(record) };
  }

  /** 使用现有 AES-GCM 与记录 AAD，正文中的链接也只存在于密文中。 */
  encrypt(text: string, id: string): Uint8Array<ArrayBuffer> {
    return this.cipher.encrypt(text, `IngestionRecord:${id}:rawContent`);
  }

  /** 用户及渠道域隔离的 HMAC 内容索引，避免低熵文字的无密钥摘要。 */
  hash(text: string, userId: string): string {
    return Buffer.from(this.cipher.blindIndex(text, `IngestionRecord:${userId}:WECHAT:rawContent:v1`)).toString('hex');
  }

  private decrypt(record: IngestionRecord): string {
    return this.cipher.decrypt(record.rawContent, `IngestionRecord:${record.id}:rawContent`);
  }
}
