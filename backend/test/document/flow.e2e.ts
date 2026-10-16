import { Account, login, register, repository, request } from '../auth/fixture';
import { newCase } from '../case/fixture';
import { installDocumentFixture, offer, content, uploadDocument, uploadInput, storage } from './fixture';
import { storageFetch } from '../storage/minio-fixture';

installDocumentFixture();
let account: Account; let access: string; let caseId: string;
beforeEach(async (): Promise<void> => {
  account = await register(); access = (await login(account)).accessToken; caseId = await newCase(access);
});

describe('文件业务真实 HTTP + MinIO 闭环', (): void => {
  it('注册登录→案件→签名直传→登记→列表→下载核对，容量和审计准确且不泄露内部键', async (): Promise<void> => {
    const ticket = await offer(access, caseId);
    const registerBody = { uploadId: ticket.uploadId, category: 'EVIDENCE' };
    const first = await request(`/cases/${caseId}/documents`, registerBody, access);
    expect(first.status).toBe(201);
    expect(first.data).toMatchObject({ version: 1, isCurrentVersion: true, isClientVisible: false,
      sizeBytes: String(content.length), source: 'MANUAL', category: 'EVIDENCE' });
    expect(first.raw.includes('storageKey')).toBe(false);
    const retry = await request(`/cases/${caseId}/documents`, registerBody, access);
    expect(retry.status).toBe(201); expect(retry.data.id).toBe(first.data.id);
    const owner = await repository.db.user.findUniqueOrThrow({ where: { id: account.id } });
    expect(owner.storageUsedBytes).toBe(BigInt(content.length));
    const list = await request(`/cases/${caseId}/documents?category=EVIDENCE`, undefined, access);
    expect(list.data.total).toBe(1);
    const download = await request(`/documents/${first.data.id as string}/download`, undefined, access);
    expect(download.status).toBe(200);
    const actual = await storageFetch(download.data.url as string);
    expect(actual.status).toBe(200);
    expect(Buffer.from(await actual.arrayBuffer()).equals(content)).toBe(true);
    expect(actual.headers.get('content-disposition')).toContain('attachment');
    const task = await request(`/cases/${caseId}/tasks`, { title: '核对虚构已上传材料', description: '虚构工作备注' }, access);
    expect(task.status).toBe(201);
    expect(task.data.caseId).toBe(caseId);
    const tasks = await request(`/cases/${caseId}/tasks`, undefined, access);
    expect(tasks.data.total).toBe(1);
    const logs = await repository.db.auditLog.findMany({ where: { caseId, resourceType: 'Document' } });
    expect(logs.map((entry): string => entry.action).sort())
      .toEqual(['DOCUMENT_DOWNLOAD_SIGNED', 'DOCUMENT_REGISTERED', 'DOCUMENT_UPLOAD_REQUESTED']);
    expect(JSON.stringify(logs).includes('X-Amz-')).toBe(false);
  });

  it('并行登记同票据只生成一个文件、一次扣额和一次审计；不同分类重放返回 409', async (): Promise<void> => {
    const ticket = await offer(access, caseId);
    const body = { uploadId: ticket.uploadId, category: 'OTHER' };
    const results = await Promise.all([request(`/cases/${caseId}/documents`, body, access), request(`/cases/${caseId}/documents`, body, access)]);
    expect(results.map((result): number => result.status)).toEqual([201, 201]);
    expect(results[0]!.data.id).toBe(results[1]!.data.id);
    expect(await repository.db.document.count({ where: { caseId } })).toBe(1);
    expect((await repository.db.user.findUniqueOrThrow({ where: { id: account.id } })).storageUsedBytes).toBe(BigInt(content.length));
    expect((await request(`/cases/${caseId}/documents`, { ...body, category: 'EVIDENCE' }, access)).status).toBe(409);
  });

});

describe('文件版本与软删除真实闭环', (): void => {
  it('乱序完成新版本仍以最大版本为当前版；分页分类、可见性审计和删除回退生效', async (): Promise<void> => {
    const first = await uploadDocument(access, caseId);
    const second = await offer(access, caseId, uploadInput({ previousDocumentId: first.id }));
    const third = await offer(access, caseId, uploadInput({ previousDocumentId: first.id }));
    expect(second.version).toBe(2); expect(third.version).toBe(3);
    const v3 = await request(`/cases/${caseId}/documents`, { uploadId: third.uploadId, category: 'OTHER' }, access);
    const v2 = await request(`/cases/${caseId}/documents`, { uploadId: second.uploadId, category: 'EVIDENCE' }, access);
    expect(v3.status).toBe(201); expect(v2.status).toBe(201); expect(v2.data.isCurrentVersion).toBe(false);
    const list = await request(`/cases/${caseId}/documents`, undefined, access);
    expect(list.data.total).toBe(1); expect((list.data.items as { id: string }[])[0]!.id).toBe(v3.data.id);
    const history = await request(`/cases/${caseId}/documents?includeHistory=true&pageSize=1`, undefined, access);
    expect(history.data.total).toBe(3); expect(history.data.items).toHaveLength(1);
    expect((await request(`/cases/${caseId}/documents?category=EVIDENCE`, undefined, access)).data.total).toBe(0);
    const visible = await request(`/documents/${v3.data.id as string}/client-visibility`, { isClientVisible: true }, access, 'PATCH');
    expect(visible.status).toBe(200); expect(visible.data.isClientVisible).toBe(true);
    expect((await request(`/documents/${v3.data.id as string}`, undefined, access, 'DELETE')).status).toBe(200);
    expect((await request(`/documents/${v3.data.id as string}/download`, undefined, access)).status).toBe(403);
    const current = await request(`/cases/${caseId}/documents`, undefined, access);
    expect((current.data.items as { id: string }[])[0]!.id).toBe(v2.data.id);
    expect((await repository.db.user.findUniqueOrThrow({ where: { id: account.id } })).storageUsedBytes).toBe(BigInt(content.length * 3));
    expect(await repository.db.auditLog.count({ where: { caseId, action: 'DOCUMENT_VISIBILITY_CHANGED' } })).toBe(1);
  });

  it('删除最后一个版本后列表为空，正式对象保留且不释放容量', async (): Promise<void> => {
    const doc = await uploadDocument(access, caseId);
    const stored = await repository.db.document.findUniqueOrThrow({ where: { id: doc.id } });
    expect((await request(`/documents/${doc.id}`, undefined, access, 'DELETE')).status).toBe(200);
    expect((await request(`/cases/${caseId}/documents`, undefined, access)).data.total).toBe(0);
    expect(await storage().exists(stored.storageKey)).toBe(true);
    expect((await repository.db.user.findUniqueOrThrow({ where: { id: account.id } })).storageUsedBytes).toBe(BigInt(content.length));
  });
});
