import { randomUUID } from 'node:crypto';
import { installFixture, register, login, createCase, request, repository } from './fixture';

installFixture();

describe('实时资源级权限', (): void => {
  it('自己案件允许，其他案件/文档/任务均 403，不能用正文指定所有者', async (): Promise<void> => {
    const owner = await register();
    const other = await register();
    const ownCase = await createCase(owner.id);
    const otherCase = await createCase(other.id);
    const document = await repository.db.document.create({ data: { caseId: otherCase, uploadedBy: other.id,
      category: 'OTHER', fileName: '虚构权限测试.txt', mimeType: 'text/plain', sizeBytes: 1n,
      storageKey: `fictional-auth/${randomUUID()}.txt` } });
    const task = await repository.db.task.create({ data: { caseId: otherCase, title: '虚构权限任务' } });
    const tokens = await login(owner);
    expect((await request(`/cases/${ownCase}/access`, undefined, tokens.accessToken)).status).toBe(200);
    for (const path of [`/cases/${otherCase}/access`, `/documents/${document.id}/access`, `/tasks/${task.id}/access`]) {
      const reply = await request(path, undefined, tokens.accessToken);
      expect(reply.status).toBe(403);
      expect(reply.raw.includes(other.id)).toBe(false);
    }
    expect((await request(`/cases/${otherCase}/access?ownerId=${owner.id}`, undefined, tokens.accessToken)).status).toBe(403);
  });
  it('文档/任务反查自己的案件可访问，软删除资源与案件立即拒绝', async (): Promise<void> => {
    const owner = await register();
    const caseId = await createCase(owner.id);
    const document = await repository.db.document.create({ data: { caseId, uploadedBy: owner.id,
      category: 'OTHER', fileName: '虚构.txt', mimeType: 'text/plain', sizeBytes: 1n, storageKey: `fictional-auth/${randomUUID()}` } });
    const task = await repository.db.task.create({ data: { caseId, title: '虚构' } });
    const tokens = await login(owner);
    expect((await request(`/documents/${document.id}/access`, undefined, tokens.accessToken)).status).toBe(200);
    expect((await request(`/tasks/${task.id}/access`, undefined, tokens.accessToken)).status).toBe(200);
    await repository.db.document.update({ where: { id: document.id }, data: { deletedAt: new Date() } });
    await repository.db.task.update({ where: { id: task.id }, data: { deletedAt: new Date() } });
    expect((await request(`/documents/${document.id}/access`, undefined, tokens.accessToken)).status).toBe(403);
    expect((await request(`/tasks/${task.id}/access`, undefined, tokens.accessToken)).status).toBe(403);
    await repository.db.case.update({ where: { id: caseId }, data: { deletedAt: new Date() } });
    expect((await request(`/cases/${caseId}/access`, undefined, tokens.accessToken)).status).toBe(403);
  });
});

describe('即时角色变更与默认拒绝', (): void => {
  it('不缓存角色：本期 VIEWER/EDITOR 不能访问，转交主办后旧 OWNER 立即失效', async (): Promise<void> => {
    const first = await register();
    const next = await register();
    const caseId = await createCase(first.id);
    await repository.db.caseMember.create({ data: { caseId, userId: next.id, invitedBy: first.id,
      role: 'VIEWER', status: 'ACCEPTED', acceptedAt: new Date() } });
    const a = await login(first);
    const b = await login(next);
    expect((await request(`/cases/${caseId}/access`, undefined, b.accessToken)).status).toBe(403);
    await repository.db.$transaction([
      repository.db.caseMember.update({ where: { caseId_userId: { caseId, userId: first.id } }, data: { role: 'EDITOR' } }),
      repository.db.caseMember.update({ where: { caseId_userId: { caseId, userId: next.id } }, data: { role: 'OWNER' } }),
      repository.db.case.update({ where: { id: caseId }, data: { ownerId: next.id } }),
    ]);
    expect((await request(`/cases/${caseId}/access`, undefined, a.accessToken)).status).toBe(403);
    expect((await request(`/cases/${caseId}/access`, undefined, b.accessToken)).status).toBe(200);
  });
  it('不存在与非法 ID 同样 403；匿名访问为 401', async (): Promise<void> => {
    const tokens = await login(await register());
    for (const path of [`/cases/${randomUUID()}/access`, '/cases/not-a-uuid/access',
      `/documents/${randomUUID()}/access`, `/tasks/${randomUUID()}/access`]) {
      expect((await request(path, undefined, tokens.accessToken)).status).toBe(403);
    }
    expect((await request(`/cases/${randomUUID()}/access`)).status).toBe(401);
  });
});
