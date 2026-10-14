import { PrismaClient, User, Case, Document } from '@prisma/client';
import { randomBytes, randomUUID } from 'node:crypto';
import { EncryptionService } from '../../src/encryption.service';

export const client = new PrismaClient();
export const cipher = new EncryptionService(randomBytes(32));

/** 所有数据均为明确虚构值；此辅助模块仅在独立测试 schema 中执行。 */
export async function createUser(): Promise<User> {
  return client.user.create({
    data: { email: `fixture-${randomUUID()}@example.invalid`, name: '虚构律师', passwordHash: 'TEST_ONLY_HASH' },
  });
}

/** 案件和 OWNER 成员同一事务落库，供数据库完整性测试使用。 */
export async function createCase(owner: User, caseNo = `虚构案号-${randomUUID()}`): Promise<Case> {
  return client.case.create({
    data: {
      ownerId: owner.id, caseNo, cause: '虚构案由', court: '虚构法院',
      members: { create: { userId: owner.id, invitedBy: owner.id, role: 'OWNER',
        status: 'ACCEPTED', acceptedAt: new Date() } },
    },
  });
}

/** 只验证数据库元数据关联，不宣称完成真实文件上传或文书定稿。 */
export async function createDocument(caseRecord: Case): Promise<Document> {
  return client.document.create({
    data: { caseId: caseRecord.id, uploadedBy: caseRecord.ownerId, category: 'OTHER',
      fileName: '虚构数据库测试材料.txt', storageKey: `schema-fixture/${randomUUID()}.txt`,
      mimeType: 'text/plain', sizeBytes: 10n },
  });
}
