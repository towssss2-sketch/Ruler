import { randomUUID } from 'node:crypto';
import { Account, login, register, repository, request } from '../auth/fixture';
import { newCase } from '../case/fixture';
import { installDocumentFixture, offer, content, uploadDocument, uploadInput } from './fixture';

installDocumentFixture();
let account: Account; let access: string; let caseId: string;
beforeEach(async (): Promise<void> => {
  account = await register(); access = (await login(account)).accessToken; caseId = await newCase(access);
});

describe('文件业务权限与并发配额', (): void => {
  it('未登录拒绝；陌生人和未开放的协作角色不能下载、改可见性、删除或申请上传', async (): Promise<void> => {
    const document = await uploadDocument(access, caseId);
    const other = await register(); const otherAccess = (await login(other)).accessToken;
    expect((await request(`/documents/${document.id}/download`)).status).toBe(401);
    for (const role of ['EDITOR', 'VIEWER'] as const) {
      await repository.db.caseMember.upsert({ where: { caseId_userId: { caseId, userId: other.id } },
        create: { caseId, userId: other.id, role, invitedBy: account.id, status: 'ACCEPTED', acceptedAt: new Date() },
        update: { role } });
      expect((await request(`/documents/${document.id}/download`, undefined, otherAccess)).status).toBe(403);
      expect((await request(`/documents/${document.id}/client-visibility`, { isClientVisible: true }, otherAccess, 'PATCH')).status).toBe(403);
      expect((await request(`/documents/${document.id}`, undefined, otherAccess, 'DELETE')).status).toBe(403);
      expect((await request(`/cases/${caseId}/documents/presign`, uploadInput(), otherAccess)).status).toBe(403);
      expect((await request(`/cases/${caseId}/documents`, undefined, otherAccess)).status).toBe(403);
    }
    expect((await request(`/documents/${randomUUID()}/download`, undefined, otherAccess)).status).toBe(403);
  });

  it('同一所有者的不同案件也不能复用上传票据或他案版本；外人票据不能被冒领', async (): Promise<void> => {
    const ticket = await offer(access, caseId);
    const secondCase = await newCase(access);
    expect((await request(`/cases/${secondCase}/documents`, { uploadId: ticket.uploadId, category: 'OTHER' }, access)).status).toBe(403);
    const document = await uploadDocument(access, caseId);
    expect((await request(`/cases/${secondCase}/documents/presign`, uploadInput({ previousDocumentId: document.id }), access)).status).toBe(403);
    const other = await register(); const token = (await login(other)).accessToken;
    const otherCase = await newCase(token);
    expect((await request(`/cases/${otherCase}/documents`, { uploadId: ticket.uploadId, category: 'OTHER' }, token)).status).toBe(403);
  });

  it('拒绝路径穿越、非法类型、超大文件、伪造键与来源、非法分类和可见性', async (): Promise<void> => {
    for (const change of [{ fileName: '../fake.pdf' }, { fileName: 'test.exe' }, { mimeType: 'text/html' },
      { sizeBytes: 209715201 }, { sizeBytes: 0 }, { contentMd5: 'invalid' }, { storageKey: 'fake' }, { ownerId: account.id }]) {
      expect((await request(`/cases/${caseId}/documents/presign`, { ...uploadInput(), ...change }, access)).status).toBe(400);
    }
    const ticket = await offer(access, caseId);
    for (const change of [{ category: 'INVALID' }, { source: 'SMS', ingestionId: randomUUID() }, { sizeBytes: 1 }]) {
      expect((await request(`/cases/${caseId}/documents`, { uploadId: ticket.uploadId, category: 'OTHER', ...change }, access)).status).toBe(400);
    }
    const document = await uploadDocument(access, caseId);
    expect((await request(`/documents/${document.id}/client-visibility`, { isClientVisible: 'true' }, access, 'PATCH')).status).toBe(400);
    expect((await request(`/cases/${caseId}/documents?includeHistory=maybe`, undefined, access)).status).toBe(400);
    expect((await request(`/cases/${caseId}/documents?category=INVALID`, undefined, access)).status).toBe(400);
  });

});

describe('跨案件配额与上传申请限制', (): void => {
  it('预签名并发预留容量，超过剩余配额返回明确 403 而不创建额外票据', async (): Promise<void> => {
    await repository.db.user.update({ where: { id: account.id }, data: { storageQuotaBytes: content.length } });
    const otherCase = await newCase(access);
    const replies = await Promise.all([request(`/cases/${caseId}/documents/presign`, uploadInput(), access),
      request(`/cases/${otherCase}/documents/presign`, uploadInput(), access)]);
    expect(replies.map((reply): number => reply.status).sort()).toEqual([201, 403]);
    expect(replies.find((reply): boolean => reply.status === 403)!.raw.includes('配额不足')).toBe(true);
    expect(await repository.db.documentUpload.count({ where: { ownerId: account.id } })).toBe(1);
  });

  it('申请后配额下降：跨案件并发登记只有一个成功，不超额且失败方可保留重试', async (): Promise<void> => {
    const secondCase = await newCase(access);
    const first = await offer(access, caseId); const second = await offer(access, secondCase);
    await repository.db.user.update({ where: { id: account.id }, data: { storageQuotaBytes: content.length } });
    const replies = await Promise.all([request(`/cases/${caseId}/documents`, { uploadId: first.uploadId, category: 'OTHER' }, access),
      request(`/cases/${secondCase}/documents`, { uploadId: second.uploadId, category: 'OTHER' }, access)]);
    expect(replies.map((reply): number => reply.status).sort()).toEqual([201, 403]);
    expect((await repository.db.user.findUniqueOrThrow({ where: { id: account.id } })).storageUsedBytes).toBe(BigInt(content.length));
    expect(await repository.db.document.count({ where: { uploadedBy: account.id } })).toBe(1);
  });

  it('案件软删除后不能登记或重新签发下载；已保留对象仍计容量', async (): Promise<void> => {
    const document = await uploadDocument(access, caseId); const ticket = await offer(access, caseId);
    expect((await request(`/cases/${caseId}`, undefined, access, 'DELETE')).status).toBe(200);
    expect((await request(`/documents/${document.id}/download`, undefined, access)).status).toBe(403);
    expect((await request(`/cases/${caseId}/documents`, { uploadId: ticket.uploadId, category: 'OTHER' }, access)).status).toBe(403);
    expect((await repository.db.user.findUniqueOrThrow({ where: { id: account.id } })).storageUsedBytes).toBe(BigInt(content.length));
  });

  it('最多允许二十个未完成申请，防止大量临时上传占用资源', async (): Promise<void> => {
    for (let index = 0; index < 20; index++) {
      expect((await request(`/cases/${caseId}/documents/presign`, uploadInput(), access)).status).toBe(201);
    }
    expect((await request(`/cases/${caseId}/documents/presign`, uploadInput(), access)).status).toBe(429);
    expect(await repository.db.documentUpload.count({ where: { ownerId: account.id } })).toBe(20);
  });

  it('兼容无上传票据的旧文档元数据；达到数据库整数版本上限时明确拒绝', async (): Promise<void> => {
    // 只准备旧记录验证版本分配，不将这两条记录声明为已上传对象。
    const legacy = await repository.db.document.create({ data: { caseId, uploadedBy: account.id, category: 'OTHER',
      fileName: '虚构旧文件.pdf', storageKey: `legacy-${randomUUID()}`, mimeType: 'application/pdf', sizeBytes: 1, version: 7 } });
    const response = await request(`/cases/${caseId}/documents/presign`, uploadInput({ previousDocumentId: legacy.id }), access);
    expect(response.status).toBe(201); expect(response.data.version).toBe(8);
    const maximum = await repository.db.document.create({ data: { caseId, uploadedBy: account.id, category: 'OTHER',
      fileName: '虚构上限.pdf', storageKey: `legacy-${randomUUID()}`, mimeType: 'application/pdf', sizeBytes: 1, version: 2147483647 } });
    expect((await request(`/cases/${caseId}/documents/presign`, uploadInput({ previousDocumentId: maximum.id }), access)).status).toBe(409);
  });
});
