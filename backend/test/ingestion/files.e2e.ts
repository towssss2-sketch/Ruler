import { randomUUID } from 'node:crypto';
import { Account, app, login, register, repository, request } from '../auth/fixture';
import { content, installDocumentFixture, storage, uploadInput } from '../document/fixture';
import { storageFetch } from '../storage/minio-fixture';
import { newCase } from '../case/fixture';
import { IngestionFileCleanupService } from '../../src/modules/ingestion/ingestion-file-cleanup.service';
import { StorageError } from '../../src/modules/document/storage/storage-error';
import * as policy from '../../src/modules/ingestion/ingestion-file-policy';
import { complete, fileOffer } from './file-fixture';

installDocumentFixture();
let account: Account; let access: string;
beforeEach(async (): Promise<void> => { account = await register(); access = (await login(account)).accessToken; });
afterEach((): void => { jest.restoreAllMocks(); });

/** 清理时间仅推进本次 sweep 的 Date.now，不更改不可变票据或鉴权时钟。 */
async function sweep(): Promise<{ cleaned: number; failed: number }> {
  const clock = jest.spyOn(Date, 'now').mockReturnValue(Date.now() + 720000);
  try { return await app.get(IngestionFileCleanupService).sweep(); } finally { clock.mockRestore(); }
}

describe('文件待定区真实 HTTP、数据库和 MinIO', (): void => {
  it('无案件上传、接收、加密待定条目与下载原字节；响应和审计不泄露内部数据', async (): Promise<void> => {
    const offer = await fileOffer(access);
    expect((await request('/ingestion/pending', undefined, access)).data.total).toBe(0);
    const reply = await complete(access, offer.uploadId); expect(reply.status).toBe(201);
    const id = reply.data.id as string;
    expect(reply.data).toMatchObject({ status: 'PENDING_MATCH', duplicate: false,
      file: { fileName: '虚构待定.pdf', sizeBytes: String(content.length), mimeType: 'application/pdf' } });
    const row = await repository.db.ingestionRecord.findUniqueOrThrow({ where: { id } });
    expect(Buffer.from(row.rawContent).includes(Buffer.from('虚构待定'))).toBe(false);
    expect(row).toMatchObject({ matchedCaseId: null, stage: 'RECEIVE', aiResult: null });
    expect((await request('/ingestion/pending', undefined, access)).data.total).toBe(1);
    const listed = (await request('/ingestion/pending', undefined, access)).data.items as Record<string, unknown>[];
    expect(listed[0]!.file).toEqual(reply.data.file);
    expect((await request(`/ingestion/${id}`, undefined, access)).data.file).toEqual(reply.data.file);
    expect(Object.keys(listed[0]!.file as object).sort()).toEqual(['fileName', 'id', 'mimeType', 'sizeBytes']);
    const metadata = await request(`/ingestion/${id}/file`, undefined, access);
    expect(Object.keys(metadata.data).sort()).toEqual(['fileName', 'id', 'mimeType', 'sizeBytes']);
    const download = await request(`/ingestion/${id}/file/download`, undefined, access);
    expect(download.status).toBe(200);
    const fetched = await storageFetch(download.data.url as string);
    expect(fetched.status).toBe(200); expect(Buffer.from(await fetched.arrayBuffer()).equals(content)).toBe(true);
    expect(new Date(download.data.expiresAt as string).getTime() - Date.now()).toBeLessThanOrEqual(600000);
    const audits = await repository.db.auditLog.findMany({ where: { userId: account.id, resourceType: 'IngestionFile' } });
    expect(audits.map((a): string => a.action).sort()).toEqual(['INGESTION_FILE_RECEIVED', 'INGESTION_UPLOAD_REQUESTED']);
    expect(audits.every((a): boolean => JSON.stringify(a.detail) === '{}')).toBe(true);
    expect(JSON.stringify(audits).includes('虚构待定')).toBe(false);
  });
  it('并发票据和重命名以真实内容去重，同票据重试和忽略后导入不重计配额', async (): Promise<void> => {
    const a = await fileOffer(access); const b = await fileOffer(access, '虚构改名.pdf');
    const replies = await Promise.all([complete(access, a.uploadId), complete(access, b.uploadId)]);
    expect(replies.map((r): number => r.status)).toEqual([201, 201]);
    expect(new Set(replies.map((r): unknown => r.data.id)).size).toBe(1);
    expect(replies.filter((r): boolean => r.data.duplicate === false)).toHaveLength(1);
    const id = replies[0]!.data.id as string;
    expect((await complete(access, a.uploadId)).data.duplicate).toBe(true);
    await request(`/ingestion/${id}/ignore`, {}, access);
    const c = await fileOffer(access, '虚构再次导入.pdf');
    expect((await complete(access, c.uploadId)).data).toMatchObject({ id, duplicate: true, status: 'IGNORED' });
    expect((await repository.db.user.findUniqueOrThrow({ where: { id: account.id } })).storageUsedBytes).toBe(BigInt(content.length));
    expect(await repository.db.ingestionFile.count({ where: { userId: account.id } })).toBe(1);
    expect((await request(`/ingestion/${id}/file/download`, undefined, access)).status).toBe(200);
    const other = await register(); const token = (await login(other)).accessToken;
    const independent = await complete(token, (await fileOffer(token)).uploadId);
    expect(independent.data.id).not.toBe(id); expect(independent.data.duplicate).toBe(false);
  });
  it('鉴权、跨用户票据与附件、软删除和伪造字段均拒绝', async (): Promise<void> => {
    const offered = await fileOffer(access); const id = (await complete(access, offered.uploadId)).data.id as string;
    const token = (await login(await register())).accessToken;
    expect((await request('/ingestion/files/presign', uploadInput())).status).toBe(401);
    expect((await complete('', offered.uploadId)).status).toBe(401);
    for (const target of [offered.uploadId, randomUUID()]) expect((await complete(token, target)).status).toBe(403);
    for (const suffix of ['file', 'file/download']) {
      expect((await request(`/ingestion/${id}/${suffix}`)).status).toBe(401);
      expect((await request(`/ingestion/${id}/${suffix}`, undefined, token)).status).toBe(403);
    }
    for (const extra of [{ caseId: randomUUID() }, { category: 'EVIDENCE' }, { previousDocumentId: randomUUID() }]) {
      expect((await request('/ingestion/files/presign', { ...uploadInput(), ...extra }, access)).status).toBe(400);
    }
    expect((await request('/ingestion/files', { uploadId: offered.uploadId, contentHash: 'fake' }, access)).status).toBe(400);
    expect((await complete(access, 'bad')).status).toBe(400);
    await repository.db.ingestionRecord.update({ where: { id }, data: { deletedAt: new Date() } });
    expect((await complete(access, offered.uploadId)).status).toBe(403);
    expect((await request(`/ingestion/${id}/file/download`, undefined, access)).status).toBe(403);
    expect((await complete(access, (await fileOffer(access)).uploadId)).status).toBe(409);
  });
  it('非法格式、大小、路径和缺失对象不能登记；没有提前占用已用空间', async (): Promise<void> => {
    for (const changes of [{ sizeBytes: 0 }, { sizeBytes: 209715201 }, { mimeType: 'text/plain' },
      { fileName: '../虚构.pdf' }, { contentMd5: 'bad' }, { fileName: '虚构.exe' }]) {
      expect((await request('/ingestion/files/presign', uploadInput(changes), access)).status).toBe(400);
    }
    const missing = await request('/ingestion/files/presign', uploadInput(), access);
    expect((await complete(access, missing.data.uploadId as string)).status).not.toBe(201);
    expect((await request('/ingestion/pending', undefined, access)).data.total).toBe(0);
    expect((await repository.db.user.findUniqueOrThrow({ where: { id: account.id } })).storageUsedBytes).toBe(0n);
  });
  it('复制、流式读取和审计故障回滚，保留票据供重试且不泄露内部错误', async (): Promise<void> => {
    const offered = await fileOffer(access);
    for (const method of ['copy', 'fingerprint'] as const) {
      const spy = jest.spyOn(storage(), method).mockRejectedValueOnce(new StorageError('UNAVAILABLE'));
      expect((await complete(access, offered.uploadId)).status).toBe(503); spy.mockRestore();
      expect(await repository.db.ingestionFile.count({ where: { userId: account.id } })).toBe(0);
    }
    const audit = jest.spyOn(policy, 'auditIngestionFile').mockRejectedValueOnce(new Error('fictional-private-audit'));
    const failed = await complete(access, offered.uploadId); audit.mockRestore();
    expect(failed.status).toBe(500); expect(failed.raw.includes('fictional-private-audit')).toBe(false);
    const ticket = await repository.db.ingestionUpload.findUniqueOrThrow({ where: { id: offered.uploadId } });
    expect(ticket.completedAt).toBeNull(); expect(await storage().exists(ticket.storageKey)).toBe(true);
    expect((await repository.db.user.findUniqueOrThrow({ where: { id: account.id } })).storageUsedBytes).toBe(0n);
    expect((await complete(access, offered.uploadId)).status).toBe(201);
  });
  it('案件与待定上传共享预约额度，并发两入口不能共同超额', async (): Promise<void> => {
    const caseId = await newCase(access);
    await repository.db.user.update({ where: { id: account.id }, data: { storageQuotaBytes: BigInt(content.length) } });
    const results = await Promise.all([request('/ingestion/files/presign', uploadInput(), access),
      request(`/cases/${caseId}/documents/presign`, uploadInput(), access)]);
    expect(results.filter((r): boolean => r.status === 201)).toHaveLength(1);
    expect(results.filter((r): boolean => r.status === 403)).toHaveLength(1);
    for (const path of ['/ingestion/files/presign', `/cases/${caseId}/documents/presign`]) {
      expect((await request(path, uploadInput(), access)).status).toBe(403);
    }
  });
  it('清理保留已接收/忽略/软删原件，删除重复副本和未完成上传，失败可重试', async (): Promise<void> => {
    const canonical = await fileOffer(access); const id = (await complete(access, canonical.uploadId)).data.id as string;
    await request(`/ingestion/${id}/ignore`, {}, access);
    const duplicate = await fileOffer(access); await complete(access, duplicate.uploadId);
    const abandoned = await fileOffer(access, '虚构放弃.pdf', Buffer.from('fictional abandoned bytes'));
    const deleted = await fileOffer(access, '虚构软删.pdf', Buffer.from('fictional retained deleted bytes'));
    const deletedId = (await complete(access, deleted.uploadId)).data.id as string;
    await repository.db.ingestionRecord.update({ where: { id: deletedId }, data: { deletedAt: new Date() } });
    const tickets = await repository.db.ingestionUpload.findMany({ where: { userId: account.id } });
    const remove = jest.spyOn(storage(), 'delete').mockRejectedValueOnce(new StorageError('UNAVAILABLE'));
    expect((await sweep()).failed).toBeGreaterThanOrEqual(1); remove.mockRestore();
    for (let i = 0; i < 5; i++) expect((await sweep()).failed).toBe(0);
    for (const ticket of tickets) {
      expect(await storage().exists(ticket.pendingKey)).toBe(false);
      expect(await storage().exists(ticket.storageKey)).toBe([canonical.uploadId, deleted.uploadId].includes(ticket.id));
    }
    expect((await complete(access, abandoned.uploadId)).status).toBe(409);
    expect((await complete(access, canonical.uploadId)).data).toMatchObject({ id, status: 'IGNORED', duplicate: true });
    expect((await request(`/ingestion/${id}/file/download`, undefined, access)).status).toBe(200);
    await repository.db.ingestionRecord.update({ where: { id }, data: { deletedAt: new Date() } });
    await sweep(); const kept = tickets.find((t): boolean => t.id === canonical.uploadId)!;
    expect(await storage().exists(kept.storageKey)).toBe(true);
  });
});
