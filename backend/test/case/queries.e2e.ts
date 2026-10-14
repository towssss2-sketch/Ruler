import { randomUUID } from 'node:crypto';
import { installFixture, login, register, repository, request } from '../auth/fixture';
import { input, newCase } from './fixture';
import { CasePage } from '../../src/modules/case/case-read.service';
import { ConflictPage } from '../../src/modules/case/case-conflict.service';

installFixture();

describe('案件列表、权限及参数边界', (): void => {
  it('分页、案号/姓名/案由搜索、法院/阶段/状态筛选及更新时间排序真实生效', async (): Promise<void> => {
    const { accessToken } = await login(await register());
    const first = input({ cause: '虚构独特案由', court: '虚构甲法院' });
    const id = await newCase(accessToken, first);
    const second = await newCase(accessToken, input({ stage: 'SECOND_INSTANCE', status: 'CLOSED' }));
    await repository.db.case.update({ where: { id }, data: { updatedAt: new Date('2026-01-01') } });
    for (const keyword of [first.caseNo, '独特案由', '东方甲乙']) {
      const reply = await request(`/cases?keyword=${encodeURIComponent(keyword)}&court=${encodeURIComponent(first.court)}`, undefined, accessToken);
      expect(reply.status).toBe(200);
      expect((reply.data.items as { id: string }[]).map((item): string => item.id)).toEqual([id]);
    }
    const page = (await request('/cases?pageSize=1&page=1&sort=desc', undefined, accessToken)).data as unknown as CasePage;
    expect(page.total).toBe(2);
    expect(page.items[0]?.id).toBe(second);
    expect(((await request('/cases?pageSize=1&page=2', undefined, accessToken)).data.items as { id: string }[])[0]?.id).toBe(id);
    expect(((await request('/cases?sort=asc', undefined, accessToken)).data.items as { id: string }[])[0]?.id).toBe(id);
    expect((await request('/cases?stage=SECOND_INSTANCE&status=CLOSED', undefined, accessToken)).data.total).toBe(1);
    const group = await request('/cases?group=collaborated', undefined, accessToken);
    expect(group.data.items).toEqual([]);
    expect(group.data.collaborationEnabled).toBe(false);
    expect((await request('/cases?page=9999', undefined, accessToken)).data.items).toEqual([]);
  });
  it('他人案件、伪造 ownerId、协作角色、不存在资源及全部六类接口均执行权限控制', async (): Promise<void> => {
    const owner = await register();
    const outsider = await register();
    const a = await login(owner);
    const b = await login(outsider);
    const id = await newCase(a.accessToken);
    for (const [suffix, method, body] of [['', 'GET', undefined], ['', 'PATCH', { cause: '越权' }],
      ['', 'DELETE', undefined], ['/conflict-check', 'POST', {}]] as const) {
      expect((await request(`/cases/${id}${suffix}`, body, b.accessToken, method)).status).toBe(403);
    }
    expect((await request('/cases', undefined, b.accessToken)).data.total).toBe(0);
    expect((await request('/cases', input())).status).toBe(401);
    expect((await request('/cases')).status).toBe(401);
    expect((await request('/cases', { ...input(), ownerId: owner.id }, b.accessToken)).status).toBe(400);
    expect((await request(`/cases/${randomUUID()}`, undefined, b.accessToken)).status).toBe(403);
    expect((await request('/cases/not-a-uuid', undefined, a.accessToken)).status).toBe(403);
    await repository.db.caseMember.create({ data: { caseId: id, userId: outsider.id, invitedBy: owner.id,
      role: 'EDITOR', status: 'ACCEPTED', acceptedAt: new Date() } });
    expect((await request(`/cases/${id}`, undefined, b.accessToken)).status).toBe(403);
  });
});

describe('利益冲突候选检查', (): void => {
  it('pg_trgm 在 0.6 边界筛选历史案件并去重，含已软删历史且不泄露其他用户案件', async (): Promise<void> => {
    const { accessToken } = await login(await register());
    const source = await newCase(accessToken);
    const exact = await newCase(accessToken);
    const fuzzy = await newCase(accessToken, input({ parties: [{ role: 'PLAINTIFF', name: '虚构东方甲乙丙丁戊' }] }));
    const low = await newCase(accessToken, input({ parties: [{ role: 'PLAINTIFF', name: '完全不同姓名' }] }));
    const outsider = await newCase((await login(await register())).accessToken);
    expect((await request(`/cases/${exact}`, undefined, accessToken, 'DELETE')).status).toBe(200);
    const result = await request(`/cases/${source}/conflict-check?pageSize=1`, {}, accessToken);
    expect(result.status).toBe(200);
    const first = result.data as unknown as ConflictPage;
    expect(first.total).toBe(2);
    expect(first.items[0]?.caseId).toBe(exact);
    expect(first.items[0]?.deleted).toBe(true);
    expect(first.items[0]?.similarity).toBe(1);
    const second = (await request(`/cases/${source}/conflict-check?pageSize=1&page=2`, {}, accessToken)).data as unknown as ConflictPage;
    expect(second.items[0]?.caseId).toBe(fuzzy);
    expect(second.items[0]!.similarity).toBeGreaterThanOrEqual(0.6);
    expect(second.items[0]!.similarity).toBeLessThan(1);
    const all = (await request(`/cases/${source}/conflict-check`, {}, accessToken)).data as unknown as ConflictPage;
    expect(all.items.some((item): boolean => [source, low, outsider].includes(item.caseId))).toBe(false);
    expect((await request(`/cases/${source}/conflict-check?page=9999`, {}, accessToken)).data).toMatchObject({ total: 2, items: [] });
    expect(await repository.db.auditLog.count({ where: { caseId: source, action: 'CASE_CONFLICT_CHECKED' } })).toBe(4);
  });
  it('零匹配返回空列表；自定义阈值/用户/SQL 片段均不能扩大查询范围', async (): Promise<void> => {
    const { accessToken } = await login(await register());
    const id = await newCase(accessToken);
    expect((await request(`/cases/${id}/conflict-check`, {}, accessToken)).data).toMatchObject({ total: 0, items: [] });
    expect((await request(`/cases/${id}/conflict-check`, { threshold: 0 }, accessToken)).status).toBe(400);
    expect((await request(`/cases/${id}/conflict-check?page=0`, {}, accessToken)).status).toBe(400);
    expect((await request('/cases?keyword=%27%20OR%201%3D1--', undefined, accessToken)).data.total).toBe(0);
  });
});
