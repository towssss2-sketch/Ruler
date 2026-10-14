import { baseUrl, installFixture, login, register, repository, request } from '../auth/fixture';
import { input, newCase } from './fixture';

installFixture();

describe('案件 HTTP 契约与并发归档', (): void => {
  it('非法正文、重复页码和无界查询返回 400，Swagger 列出真实输入与六类操作', async (): Promise<void> => {
    const { accessToken } = await login(await register());
    for (const change of [{ fee: 0.1 }, { caseNo: '无效案号' }, { parties: [] }, { notes: {} }]) {
      expect((await request('/cases', { ...input(), ...change }, accessToken)).status).toBe(400);
    }
    for (const query of ['page=1&page=2', 'pageSize=101', 'ownerId=forged']) {
      expect((await request(`/cases?${query}`, undefined, accessToken)).status).toBe(400);
    }
    const id = await newCase(accessToken);
    expect((await request(`/cases/${id}`, {}, accessToken, 'PATCH')).status).toBe(400);
    const response = await fetch(`${baseUrl}/docs-json`);
    const doc = await response.json() as { paths: Record<string, Record<string, { requestBody?: unknown }>> };
    expect(Object.keys(doc.paths['/cases']!).sort()).toEqual(['get', 'post']);
    expect(Object.keys(doc.paths['/cases/{caseId}']!).sort()).toEqual(['delete', 'get', 'patch']);
    expect(doc.paths['/cases/{caseId}/conflict-check']?.post).toBeDefined();
    expect(JSON.stringify(doc.paths['/cases']?.post?.requestBody)).toContain('parties');
  });
  it('并发修改和删除按案件锁串行，删除后不会残留可见当事人或成功复活案件', async (): Promise<void> => {
    const { accessToken } = await login(await register());
    const id = await newCase(accessToken);
    const [changed, removed] = await Promise.all([
      request(`/cases/${id}`, { parties: [{ role: 'PLAINTIFF', name: '虚构并发当事人' }] }, accessToken, 'PATCH'),
      request(`/cases/${id}`, undefined, accessToken, 'DELETE'),
    ]);
    expect([200, 403]).toContain(changed.status);
    expect(removed.status).toBe(200);
    expect(await repository.db.caseParty.count({ where: { caseId: id, deletedAt: null } })).toBe(0);
    expect((await request(`/cases/${id}`, { cause: '不得复活' }, accessToken, 'PATCH')).status).toBe(403);
  });
});
