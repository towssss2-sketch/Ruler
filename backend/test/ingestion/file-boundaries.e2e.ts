import { randomUUID } from 'node:crypto';
import { Account, app, login, register, repository, request } from '../auth/fixture';
import { content, installDocumentFixture, storage, uploadInput } from '../document/fixture';
import { newCase } from '../case/fixture';
import { IngestionFileRegisterService } from '../../src/modules/ingestion/ingestion-file-register.service';
import { IngestionFileReadService } from '../../src/modules/ingestion/ingestion-file-read.service';
import { ingestionStorageKey } from '../../src/modules/document/storage/storage-policy';
import { StorageError } from '../../src/modules/document/storage/storage-error';
import { complete, fileOffer } from './file-fixture';

installDocumentFixture();
let account: Account; let access: string;
beforeEach(async (): Promise<void> => { account = await register(); access = (await login(account)).accessToken; });
afterEach((): void => { jest.restoreAllMocks(); });

describe('文件暂存额度、内容和授权边界', (): void => {
  it('两个入口共享最多二十张有效票据限制', async (): Promise<void> => {
    const caseId = await newCase(access);
    for (let i = 0; i < 20; i++) {
      const path = i % 2 ? '/ingestion/files/presign' : `/cases/${caseId}/documents/presign`;
      expect((await request(path, uploadInput(), access)).status).toBe(201);
    }
    for (const path of ['/ingestion/files/presign', `/cases/${caseId}/documents/presign`]) {
      expect((await request(path, uploadInput(), access)).status).toBe(429);
    }
  });
  it('已用容量同样约束两入口；登记时额度降低也必须重新核验', async (): Promise<void> => {
    const first = await fileOffer(access); const second = await fileOffer(access, '虚构另一文件.pdf', Buffer.from('different fictional bytes'));
    const id = (await complete(access, first.uploadId)).data.id as string;
    await repository.db.user.update({ where: { id: account.id }, data: { storageQuotaBytes: BigInt(content.length) } });
    expect((await complete(access, second.uploadId)).status).toBe(403);
    expect((await request('/ingestion/files/presign', uploadInput(), access)).status).toBe(403);
    const caseId = await newCase(access);
    expect((await request(`/cases/${caseId}/documents/presign`, uploadInput(), access)).status).toBe(403);
    expect((await request(`/ingestion/${id}/file`, undefined, access)).status).toBe(200);
  });
  it('过期票据无法登记，账号停用后服务也无法绕过授权', async (): Promise<void> => {
    const offered = await fileOffer(access);
    const ticket = await repository.db.ingestionUpload.findUniqueOrThrow({ where: { id: offered.uploadId } });
    const expired = await repository.db.ingestionUpload.create({ data: { userId: account.id, fileName: ticket.fileName,
      mimeType: ticket.mimeType, sizeBytes: ticket.sizeBytes, contentMd5: ticket.contentMd5,
      pendingKey: ingestionStorageKey(account.id, randomUUID(), randomUUID(), '虚构.pdf'),
      storageKey: ingestionStorageKey(account.id, randomUUID(), randomUUID(), '虚构.pdf'), expiresAt: new Date(0) } });
    expect((await complete(access, expired.id)).status).toBe(409);
    const id = (await complete(access, offered.uploadId)).data.id as string;
    await repository.db.user.update({ where: { id: account.id }, data: { deletedAt: new Date() } });
    await expect(app.get(IngestionFileRegisterService).register(account.id, offered.uploadId)).rejects.toThrow();
    await expect(app.get(IngestionFileReadService).download(account.id, id)).rejects.toThrow();
  });
  it('上传与冻结副本都核验实际元数据，不能只相信申请字段', async (): Promise<void> => {
    const offered = await fileOffer(access); const realStat = storage().stat.bind(storage());
    const mismatch = { sizeBytes: content.length + 1, mimeType: 'application/pdf', etag: 'abcd' };
    for (const frozen of [false, true]) {
      const spy = jest.spyOn(storage(), 'stat');
      if (frozen) spy.mockImplementationOnce(realStat);
      spy.mockResolvedValueOnce(mismatch);
      expect((await complete(access, offered.uploadId)).status).toBe(409); spy.mockRestore();
      expect(await repository.db.ingestionFile.count({ where: { userId: account.id } })).toBe(0);
    }
    expect((await complete(access, offered.uploadId)).status).toBe(201);
  });
  it('相同名字不同实际内容形成两份材料，普通文字不与文件互相去重', async (): Promise<void> => {
    const first = await complete(access, (await fileOffer(access)).uploadId);
    const second = await complete(access, (await fileOffer(access, '虚构待定.pdf', Buffer.from('different fictional file'))).uploadId);
    expect(second.data.id).not.toBe(first.data.id); expect(second.data.duplicate).toBe(false);
    const text = await request('/ingestion/wechat', { rawContent: '手动导入文件：虚构待定.pdf' }, access);
    expect(text.data.id).not.toBe(first.data.id);
    expect((await request(`/ingestion/${text.data.id as string}/file`, undefined, access)).status).toBe(403);
    expect((await request('/ingestion/pending', undefined, access)).data.total).toBe(3);
  });
  it('下载对象缺失统一拒绝，存储故障返回固定错误，可恢复重试', async (): Promise<void> => {
    const id = (await complete(access, (await fileOffer(access)).uploadId)).data.id as string;
    const exists = jest.spyOn(storage(), 'exists').mockResolvedValueOnce(false);
    expect((await request(`/ingestion/${id}/file/download`, undefined, access)).status).toBe(403); exists.mockRestore();
    const signed = jest.spyOn(storage(), 'getDownloadUrl').mockRejectedValueOnce(new StorageError('UNAVAILABLE'));
    expect((await request(`/ingestion/${id}/file/download`, undefined, access)).status).toBe(503); signed.mockRestore();
    expect((await request(`/ingestion/${id}/file/download`, undefined, access)).status).toBe(200);
  });
});
