import { randomBytes, randomUUID } from 'node:crypto';
import { Account, app, login, register, repository, request } from '../auth/fixture';
import { newCase } from '../case/fixture';
import { installDocumentFixture, content, uploadInput } from './fixture';
import { storageFetch } from '../storage/minio-fixture';
import { EncryptionService } from '../../src/encryption.service';
import { DocumentUploadService } from '../../src/modules/document/document-upload.service';

installDocumentFixture();
let account: Account; let access: string; let caseId: string;
beforeEach(async (): Promise<void> => {
  account = await register(); access = (await login(account)).accessToken; caseId = await newCase(access);
});

/** 只建立虚构已匹配归集记录；不连接任何真实短信、邮件或法院平台。 */
async function ingestion(userId: string, matchedCaseId: string): Promise<string> {
  const id = randomUUID();
  await repository.db.ingestionRecord.create({ data: { id, userId, matchedCaseId, channel: 'SMS', status: 'MATCHED',
    contentHash: randomBytes(32).toString('hex'), rawContent: app.get(EncryptionService).encrypt('虚构短信', `IngestionRecord:${id}:rawContent`) } });
  return id;
}

describe('内部归集来源与文件登记契约（非真实渠道接入）', (): void => {
  it('内部入口绑定正确来源，真实直传后元数据和数据库关联一致', async (): Promise<void> => {
    const ingestionId = await ingestion(account.id, caseId);
    const service = app.get(DocumentUploadService);
    const ticket = await service.presign(account.id, caseId, uploadInput(), { source: 'SMS', ingestionId });
    const uploaded = await storageFetch(ticket.url, { method: 'PUT', headers: ticket.headers, body: content });
    expect(uploaded.status).toBe(200); await uploaded.arrayBuffer();
    const result = await request(`/cases/${caseId}/documents`, { uploadId: ticket.uploadId, category: 'SUMMONS' }, access);
    expect(result.status).toBe(201); expect(result.data).toMatchObject({ source: 'SMS', ingestionId });
  });
  it('他人、跨案件、渠道不符或已删除的归集来源均被拒绝；登记时再次检查', async (): Promise<void> => {
    const other = await register(); const otherCase = await newCase(access);
    const foreign = await ingestion(other.id, caseId); const cross = await ingestion(account.id, otherCase);
    const own = await ingestion(account.id, caseId); const service = app.get(DocumentUploadService);
    for (const ingestionId of [foreign, cross]) {
      await expect(service.presign(account.id, caseId, uploadInput(), { source: 'SMS', ingestionId })).rejects.toMatchObject({ status: 403 });
    }
    await expect(service.presign(account.id, caseId, uploadInput(), { source: 'EMAIL', ingestionId: own })).rejects.toMatchObject({ status: 403 });
    const ticket = await service.presign(account.id, caseId, uploadInput(), { source: 'SMS', ingestionId: own });
    await repository.db.ingestionRecord.update({ where: { id: own }, data: { deletedAt: new Date() } });
    expect((await request(`/cases/${caseId}/documents`, { uploadId: ticket.uploadId, category: 'OTHER' }, access)).status).toBe(403);
  });
});
