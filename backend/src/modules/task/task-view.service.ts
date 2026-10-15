import { Injectable } from '@nestjs/common';
import { Task } from '@prisma/client';
import { EncryptionService } from '../../encryption.service';

export type TaskView = Omit<Task, 'description' | 'deletedAt'> & { description: string | null };

@Injectable()
export class TaskViewService {
  constructor(private readonly cipher: EncryptionService) {}

  /** 授权后解密描述；AAD 绑定任务 UUID，密文损坏则失败而不返回部分明文。 */
  view(record: Task): TaskView {
    const { description, deletedAt, ...result } = record;
    void deletedAt;
    return { ...result, description: description ? this.cipher.decrypt(description, `Task:${record.id}:description`) : null };
  }

  /** 描述省略保留、null 清空，非空文本 AES-GCM 加密后落库。 */
  encrypt(value: string | null | undefined, id: string): Uint8Array<ArrayBuffer> | null | undefined {
    return value === undefined || value === null ? value : this.cipher.encrypt(value, `Task:${id}:description`);
  }
}
