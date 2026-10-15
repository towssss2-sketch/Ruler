import { randomUUID } from 'node:crypto';
import { Account, app, login, register, repository, request } from '../auth/fixture';
import { newCase } from '../case/fixture';
import { installDocumentFixture, offer, uploadDocument, uploadInput, storage, content } from './fixture';
import { StorageError } from '../../src/modules/document/storage/storage-error';
import { DocumentCleanupService } from '../../src/modules/document/document-cleanup.service';
import * as policy from '../../src/modules/document/document-policy';
import { storageFetch } from '../storage/minio-fixture';

installDocumentFixture();
let account: Account; let access: string; let caseId: string;
beforeEach(async (): Promise<void> => {
  account = await register(); access = (await login(account)).accessToken; caseId = await newCase(access);
});
afterEach((): void => { jest.restoreAllMocks(); });

describe('文件事务与存储故障恢复', (): void => {
  it('尚未上传不能登记；无正文对象不会产生文档或容量', async (): Promise<void> => {
    const signed = await request(`/cases/${caseId}/documents/presign`, uploadInput(), access);
    expect(signed.status).toBe(201);
    const reply = await request(`/cases/${caseId}/documents`, { uploadId: signed.data.uploadId, category: 'OTHER' }, access);
    expect(reply.status).toBe(409);
    expect(await repository.db.document.count({ where: { caseId } })).toBe(0);
    expect((await repository.db.user.findUniqueOrThrow({ where: { id: account.id } })).storageUsedBytes).toBe(0n);
  });

  it('复制失败返回安全 503，重试后成功且只计一次容量', async (): Promise<void> => {
    const signed = await offer(access, caseId);
    const spy = jest.spyOn(storage(), 'copy').mockRejectedValueOnce(new StorageError('UNAVAILABLE'));
    const reply = await request(`/cases/${caseId}/documents`, { uploadId: signed.uploadId, category: 'OTHER' }, access);
    expect(reply.status).toBe(503); expect(reply.raw.includes('X-Amz-')).toBe(false);
    expect(await repository.db.document.count({ where: { caseId } })).toBe(0);
    spy.mockRestore();
    expect((await request(`/cases/${caseId}/documents`, { uploadId: signed.uploadId, category: 'OTHER' }, access)).status).toBe(201);
    expect((await repository.db.user.findUniqueOrThrow({ where: { id: account.id } })).storageUsedBytes).toBe(BigInt(content.length));
  });

  it('复制成功后数据库写入失败会回滚文件、配额和审计；目标保留在票据中可安全重试', async (): Promise<void> => {
    const signed = await offer(access, caseId);
    const spy = jest.spyOn(policy, 'auditDocument').mockRejectedValueOnce(new Error('fictional-database-failure'));
    const reply = await request(`/cases/${caseId}/documents`, { uploadId: signed.uploadId, category: 'OTHER' }, access);
    expect(reply.status).toBe(500); expect(reply.raw.includes('fictional-database-failure')).toBe(false);
    const ticket = await repository.db.documentUpload.findUniqueOrThrow({ where: { id: signed.uploadId } });
    expect(ticket.completedAt).toBeNull(); expect(await storage().exists(ticket.storageKey)).toBe(true);
    expect(await repository.db.document.count({ where: { caseId } })).toBe(0);
    expect((await repository.db.user.findUniqueOrThrow({ where: { id: account.id } })).storageUsedBytes).toBe(0n);
    spy.mockRestore();
    expect((await request(`/cases/${caseId}/documents`, { uploadId: signed.uploadId, category: 'OTHER' }, access)).status).toBe(201);
  });

});

describe('旧链接隔离与过期回收', (): void => {
  it('旧上传地址再次上传只影响临时对象，不覆盖已登记正式对象', async (): Promise<void> => {
    const signed = await offer(access, caseId);
    const registered = await request(`/cases/${caseId}/documents`, { uploadId: signed.uploadId, category: 'OTHER' }, access);
    expect(registered.status).toBe(201);
    const ticket = await repository.db.documentUpload.findUniqueOrThrow({ where: { id: signed.uploadId } });
    expect(ticket.pendingKey === ticket.storageKey).toBe(false);
    const replay = await storageFetch(signed.url, { method: 'PUT', headers: signed.headers, body: content });
    expect(replay.status).toBe(200); await replay.arrayBuffer();
    const copy = jest.spyOn(storage(), 'copy');
    expect((await request(`/cases/${caseId}/documents`, { uploadId: signed.uploadId, category: 'OTHER' }, access)).status).toBe(201);
    expect(copy).not.toHaveBeenCalled();
    expect(await storage().exists(ticket.storageKey)).toBe(true);
  });

  it('正式对象丢失返回明确失败，不签发误导性下载链接', async (): Promise<void> => {
    const document = await uploadDocument(access, caseId);
    const record = await repository.db.document.findUniqueOrThrow({ where: { id: document.id } });
    await storage().delete(record.storageKey);
    expect((await request(`/documents/${document.id}/download`, undefined, access)).status).toBe(409);
  });

  it('原版本全部删除后未完成版本登记被拒绝，不能借票据复活文件', async (): Promise<void> => {
    const document = await uploadDocument(access, caseId);
    const signed = await offer(access, caseId, uploadInput({ previousDocumentId: document.id }));
    expect((await request(`/documents/${document.id}`, undefined, access, 'DELETE')).status).toBe(200);
    expect((await request(`/cases/${caseId}/documents`, { uploadId: signed.uploadId, category: 'OTHER' }, access)).status).toBe(409);
  });

  it('过期票据禁止登记；回收失败保留记录重试，成功后只清理该票据的孤立对象', async (): Promise<void> => {
    const signed = await offer(access, caseId);
    const active = await repository.db.documentUpload.findUniqueOrThrow({ where: { id: signed.uploadId } });
    const id = randomUUID(); const documentId = randomUUID();
    const expired = await repository.db.documentUpload.create({ data: { ...active, id, documentId,
      versionGroupId: randomUUID(), pendingKey: active.pendingKey.replace(active.pendingKey.split('/')[2]!, id),
      storageKey: active.storageKey.replace(active.documentId, documentId), expiresAt: new Date(Date.now() - 120000) } });
    await storage().copy(active.pendingKey, expired.pendingKey);
    await storage().copy(active.pendingKey, expired.storageKey);
    expect((await request(`/cases/${caseId}/documents`, { uploadId: id, category: 'OTHER' }, access)).status).toBe(409);
    const cleanup = app.get(DocumentCleanupService);
    const failed = jest.spyOn(storage(), 'delete').mockRejectedValueOnce(new StorageError('UNAVAILABLE'));
    expect((await cleanup.sweep()).failed).toBe(1); failed.mockRestore();
    expect((await repository.db.documentUpload.findUniqueOrThrow({ where: { id } })).cleanedAt).toBeNull();
    expect((await cleanup.sweep()).cleaned).toBe(1);
    expect(await storage().exists(expired.pendingKey)).toBe(false); expect(await storage().exists(expired.storageKey)).toBe(false);
    expect(await storage().exists(active.pendingKey)).toBe(true);
  });
});
