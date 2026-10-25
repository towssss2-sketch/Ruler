import { randomUUID } from 'node:crypto';
import { DocumentCategory } from '@prisma/client';
import { Account, app, login, register, repository, request } from '../auth/fixture';
import { content, installDocumentFixture, storage } from '../document/fixture';
import { storageFetch } from '../storage/minio-fixture';
import { newCase } from '../case/fixture';
import { complete, fileOffer } from './file-fixture';
import { StorageError } from '../../src/modules/document/storage/storage-error';
import { DocumentCleanupService } from '../../src/modules/document/document-cleanup.service';
import * as policy from '../../src/modules/document/document-policy';

installDocumentFixture();
let account: Account; let access: string; let caseId: string; let id: string;
beforeEach(async (): Promise<void> => {
  account = await register(); access = (await login(account)).accessToken;
  caseId = await newCase(access); id = (await complete(access, (await fileOffer(access)).uploadId)).data.id as string;
});
afterEach((): void => { jest.restoreAllMocks(); });
function assign(category: DocumentCategory = 'SERVICE_CONTRACT', target = caseId): ReturnType<typeof request> {
  return request(`/ingestion/${id}/assign`, { caseId: target, category }, access);
}
async function sweep(): Promise<void> {
  const clock = jest.spyOn(Date, 'now').mockReturnValue(Date.now() + 720000);
  try { for (let i = 0; i < 5; i++) expect((await app.get(DocumentCleanupService).sweep()).failed).toBe(0); }
  finally { clock.mockRestore(); }
}

describe('待定附件人工分类归档真实 HTTP/MinIO', (): void => {
  it('生成正式案件文件、保留原件、移出待定并在重登后按类下载，容量及审计一致', async (): Promise<void> => {
    const result = await assign(); expect(result.status).toBe(201);
    expect(result.data).toMatchObject({ caseId, category: 'SERVICE_CONTRACT', source: 'WECHAT', ingestionId: id,
      version: 1, isCurrentVersion: true, isClientVisible: false });
    expect(result.data).not.toHaveProperty('storageKey');
    access = (await login(account)).accessToken;
    const listing = await request(`/cases/${caseId}/documents?category=SERVICE_CONTRACT`, undefined, access);
    expect(listing.data.total).toBe(1);
    expect((await request('/ingestion/pending', undefined, access)).data.total).toBe(0);
    expect((await request(`/ingestion/${id}`, undefined, access)).data.status).toBe('ASSIGNED');
    for (const path of [`/documents/${result.data.id}/download`, `/ingestion/${id}/file/download`]) {
      const signed = await request(path, undefined, access); expect(signed.status).toBe(200);
      const downloaded = await storageFetch(signed.data.url as string);
      expect(Buffer.from(await downloaded.arrayBuffer()).equals(content)).toBe(true);
    }
    expect((await repository.db.user.findUniqueOrThrow({ where: { id: account.id } })).storageUsedBytes).toBe(BigInt(content.length * 2));
    const logs = await repository.db.auditLog.findMany({ where: { userId: account.id, action: 'INGESTION_FILE_ASSIGNED' } });
    expect(logs).toHaveLength(1); expect(logs[0]!.detail).toEqual({ category: 'SERVICE_CONTRACT' });
    expect(await repository.db.task.count({ where: { caseId } })).toBe(0);
    await sweep(); expect((await assign()).data.id).toBe(result.data.id);
  });
  it('全部 11 分类均可归档，分类查询不混入其他类别', async (): Promise<void> => {
    for (const category of Object.values(DocumentCategory)) {
      id = (await complete(access, (await fileOffer(access, '虚构分类.pdf', Buffer.from(`fictional-${category}`))).uploadId)).data.id as string;
      expect((await assign(category)).status).toBe(201);
      const result = await request(`/cases/${caseId}/documents?category=${category}`, undefined, access);
      expect(result.data.total).toBe(1);
      expect((result.data.items as { category: string }[]).every((d): boolean => d.category === category)).toBe(true);
    }
  });
  it('并发及重试只创建一份；不同案件/分类冲突，不能忽略或删除后重新生成', async (): Promise<void> => {
    const replies = await Promise.all([assign(), assign(), assign()]);
    expect(replies.map((r): number => r.status)).toEqual([201, 201, 201]);
    expect(new Set(replies.map((r): unknown => r.data.id)).size).toBe(1);
    expect((await assign('PLEADING')).status).toBe(409);
    expect((await assign('SERVICE_CONTRACT', await newCase(access))).status).toBe(409);
    expect((await request(`/ingestion/${id}/ignore`, {}, access)).status).toBe(409);
    await request(`/documents/${replies[0]!.data.id}`, undefined, access, 'DELETE');
    expect((await assign()).status).toBe(409);
    expect(await repository.db.document.count({ where: { ingestionId: id } })).toBe(1);
  });
  it('拒绝无登录、他人材料/案件、删除资源、非法分类和伪造字段', async (): Promise<void> => {
    const other = (await login(await register())).accessToken; const foreignCase = await newCase(other);
    const body = { caseId, category: 'PLEADING' };
    expect((await request(`/ingestion/${id}/assign`, body)).status).toBe(401);
    expect((await request(`/ingestion/${id}/assign`, { ...body, caseId: foreignCase }, other)).status).toBe(403);
    expect((await request(`/ingestion/${id}/assign`, { ...body, caseId: foreignCase }, access)).status).toBe(403);
    expect((await request(`/ingestion/${randomUUID()}/assign`, body, access)).status).toBe(403);
    for (const extra of [{ category: 'BAD' }, { caseId: 'bad' }, { source: 'SMS' }, { storageKey: 'fake' }, { userId: account.id }]) {
      expect((await request(`/ingestion/${id}/assign`, { ...body, ...extra }, access)).status).toBe(400);
    }
    await request(`/cases/${caseId}`, undefined, access, 'DELETE');
    expect((await assign()).status).toBe(403);
    caseId = await newCase(access);
    await repository.db.ingestionRecord.update({ where: { id }, data: { deletedAt: new Date() } });
    expect((await assign()).status).toBe(403);
  });
  it('文字和忽略材料不能转文件；配额不足不改状态、不提前创建票据或文档', async (): Promise<void> => {
    const text = await request('/ingestion/wechat', { rawContent: '虚构仅文字' }, access);
    expect((await request(`/ingestion/${text.data.id}/assign`, { caseId, category: 'OTHER' }, access)).status).toBe(409);
    await repository.db.user.update({ where: { id: account.id }, data: { storageQuotaBytes: BigInt(content.length) } });
    expect((await assign()).status).toBe(403);
    expect(await repository.db.documentUpload.count({ where: { ingestionId: id } })).toBe(0);
    expect((await request(`/ingestion/${id}`, undefined, access)).data.status).toBe('PENDING_MATCH');
    await request(`/ingestion/${id}/ignore`, {}, access); expect((await assign()).status).toBe(409);
  });
  it('复制/审计失败回滚并复用票据；公共登记不能绕过待定状态；清理不删除保留原件', async (): Promise<void> => {
    const copy = jest.spyOn(storage(), 'copy').mockRejectedValueOnce(new StorageError('UNAVAILABLE'));
    expect((await assign()).status).toBe(503); copy.mockRestore();
    const ticket = await repository.db.documentUpload.findFirstOrThrow({ where: { ingestionId: id } });
    expect((await request(`/cases/${caseId}/documents`, { uploadId: ticket.id, category: 'SERVICE_CONTRACT' }, access)).status).toBe(403);
    const audit = jest.spyOn(policy, 'auditDocument').mockRejectedValueOnce(new Error('fictional-private-audit'));
    const failed = await assign(); audit.mockRestore();
    expect(failed.status).toBe(500); expect(failed.raw.includes('fictional-private-audit')).toBe(false);
    expect(await storage().exists(ticket.storageKey)).toBe(true);
    expect(await repository.db.document.count({ where: { ingestionId: id } })).toBe(0);
    expect((await repository.db.ingestionRecord.findUniqueOrThrow({ where: { id } })).status).toBe('PENDING_MATCH');
    expect((await repository.db.user.findUniqueOrThrow({ where: { id: account.id } })).storageUsedBytes).toBe(BigInt(content.length));
    expect((await assign()).data.id).toBe(ticket.documentId);
    expect(await repository.db.documentUpload.count({ where: { ingestionId: id } })).toBe(1);
    await sweep(); expect(await storage().exists(ticket.storageKey)).toBe(true);
  });
  it('失败归档副本能回收，原件保留；过期后重新提交成功', async (): Promise<void> => {
    const audit = jest.spyOn(policy, 'auditDocument').mockRejectedValueOnce(new Error('fictional failure'));
    expect((await assign()).status).toBe(500); audit.mockRestore();
    const ticket = await repository.db.documentUpload.findFirstOrThrow({ where: { ingestionId: id } });
    const file = await repository.db.ingestionFile.findUniqueOrThrow({ where: { ingestionId: id } });
    const remove = jest.spyOn(storage(), 'delete').mockRejectedValueOnce(new StorageError('UNAVAILABLE'));
    const clock = jest.spyOn(Date, 'now').mockReturnValue(Date.now() + 720000);
    expect((await app.get(DocumentCleanupService).sweep()).failed).toBeGreaterThan(0); clock.mockRestore(); remove.mockRestore();
    await sweep(); expect(await storage().exists(ticket.storageKey)).toBe(false);
    expect(await storage().exists(file.storageKey)).toBe(true);
    expect((await assign()).status).toBe(201);
  });
  it('跨案件同时指派以及忽略竞争最多一个成功状态，无重复文档或计量', async (): Promise<void> => {
    const otherCase = await newCase(access);
    const replies = await Promise.all([assign(), assign('COURT_DOCUMENT', otherCase), request(`/ingestion/${id}/ignore`, {}, access)]);
    expect(replies.every((r): boolean => [201, 409].includes(r.status))).toBe(true);
    const count = await repository.db.document.count({ where: { ingestionId: id } });
    expect(count).toBeLessThanOrEqual(1);
    const row = await repository.db.ingestionRecord.findUniqueOrThrow({ where: { id } });
    expect(row.status).toBe(count ? 'ASSIGNED' : 'IGNORED');
    expect((await repository.db.user.findUniqueOrThrow({ where: { id: account.id } })).storageUsedBytes).toBe(BigInt(content.length * (1 + count)));
  });
});
