import { installFixture, login, register, repository, request } from '../auth/fixture';
import { input, newCase } from './fixture';
import { CasePage } from '../../src/modules/case/case-read.service';
import { caseQuery } from '../../src/modules/case/case-input';

installFixture();
const number = '(2026)虚构民初90号';
const route = (value = number): string => `/cases?caseNo=${encodeURIComponent(value)}`;

describe('完整案号精确匹配本人案件', (): void => {
  it('同号多法院全部分页返回、稳定排序；案由引用、相似号与已删除记录不匹配', async (): Promise<void> => {
    const { accessToken } = await login(await register());
    const ids: string[] = [];
    for (const court of ['虚构甲法院', '虚构乙法院', '虚构丙法院']) {
      ids.push(await newCase(accessToken, input({ caseNo: number, court })));
    }
    const removed = await newCase(accessToken, input({ caseNo: number, court: '虚构已删法院' }));
    expect((await request(`/cases/${removed}`, undefined, accessToken, 'DELETE')).status).toBe(200);
    await newCase(accessToken, input({ caseNo: '(2026)虚构民初190号', cause: number }));
    await repository.db.case.updateMany({ where: { id: { in: ids } }, data: { updatedAt: new Date('2026-01-01') } });
    const found: string[] = [];
    for (const page of [1, 2, 3]) {
      const reply = await request(`${route()}&pageSize=1&page=${page}&sort=asc`, undefined, accessToken);
      expect(reply.status).toBe(200);
      const result = reply.data as unknown as CasePage;
      expect(result.total).toBe(3);
      expect(result.items).toHaveLength(1);
      expect(Object.keys(result.items[0]!).sort()).toEqual(['caseNo', 'cause', 'court', 'id', 'stage', 'status', 'updatedAt']);
      expect(result.items[0]!.caseNo).toBe(number);
      found.push(result.items[0]!.id);
    }
    expect(found).toEqual([...ids].sort());
    expect((await request(`${route()}&page=9999`, undefined, accessToken)).data).toMatchObject({ total: 3, items: [] });
  });

  it('归一化括号空白，与原关键词/法院/状态/阶段取交集；结案仍可人工选择', async (): Promise<void> => {
    const { accessToken } = await login(await register());
    const id = await newCase(accessToken, input({ caseNo: number, cause: '虚构特殊案由', status: 'CLOSED', stage: 'SECOND_INSTANCE' }));
    const reply = await request(`${route(' （2026） 虚构民初90号 ')}&keyword=${encodeURIComponent('特殊')}&status=CLOSED&stage=SECOND_INSTANCE`, undefined, accessToken);
    expect(reply.status).toBe(200);
    expect((reply.data.items as { id: string }[]).map((row): string => row.id)).toEqual([id]);
    for (const filter of ['status=ACTIVE', 'stage=FIRST_INSTANCE', `court=${encodeURIComponent('虚构其他法院')}`, 'keyword=no-match']) {
      expect((await request(`${route()}&${filter}`, undefined, accessToken)).data.total).toBe(0);
    }
  });

  it('不泄露他人/协作预留案件，不存在与无权限同为空；无写入副作用', async (): Promise<void> => {
    const owner = await register(), outsider = await register();
    const a = await login(owner), b = await login(outsider);
    const id = await newCase(a.accessToken, input({ caseNo: number }));
    await repository.db.caseMember.create({ data: { caseId: id, userId: outsider.id, invitedBy: owner.id,
      role: 'EDITOR', status: 'ACCEPTED', acceptedAt: new Date() } });
    const before = await repository.db.auditLog.count();
    for (const path of [route(), route('(2026)虚构民初999号'), `${route()}&group=collaborated`]) {
      const reply = await request(path, undefined, b.accessToken);
      expect(reply.status).toBe(200);
      expect(reply.data).toMatchObject({ total: 0, items: [], collaborationEnabled: false });
      expect(reply.raw.includes(id)).toBe(false);
    }
    expect((await request(route())).status).toBe(401);
    expect((await request(`${route()}&ownerId=${owner.id}`, undefined, b.accessToken)).status).toBe(400);
    expect(await repository.db.auditLog.count()).toBe(before);
  });

  it('非法、空、重复和注入案号返回400，不降级为全量搜索', async (): Promise<void> => {
    const { accessToken } = await login(await register());
    await newCase(accessToken, input({ caseNo: number }));
    for (const path of [route(''), route('   '), route('90'), route('%'), route("' OR 1=1--"),
      route('null'), route('x'.repeat(81)), `${route()}&caseNo=${encodeURIComponent(number)}`]) {
      expect((await request(path, undefined, accessToken)).status).toBe(400);
    }
    expect((await request('/cases', undefined, accessToken)).data.total).toBe(1);
  });
});

describe('精确案号查询 DTO', (): void => {
  it('归一化但不修改输入，省略条件保留原查询', (): void => {
    const raw = { caseNo: ' （2026） 虚构民初90号 ', keyword: ' 虚构 ' };
    expect(caseQuery(raw)).toMatchObject({ caseNo: number, keyword: '虚构', page: '1' });
    expect(raw.caseNo).toBe(' （2026） 虚构民初90号 ');
    expect(caseQuery({}).caseNo).toBeUndefined();
  });
  it('拒绝null、数组、原型、非字符串和过长条件，支持补充汉字', (): void => {
    for (const value of [null, false, 90, [], [number], {}, '(2026)' + '民'.repeat(61) + '号']) {
      expect((): unknown => caseQuery({ caseNo: value })).toThrow();
    }
    for (const value of [null, [], 'bad', JSON.parse('{"__proto__":{}}') as unknown]) {
      expect((): unknown => caseQuery(value)).toThrow();
    }
    expect(caseQuery({ caseNo: '(2026)𠀀民初1号' }).caseNo).toBe('(2026)𠀀民初1号');
    expect(caseQuery({ caseNo: `(2026)${'𠀀'.repeat(60)}号` }).caseNo).toBe(`(2026)${'𠀀'.repeat(60)}号`);
  });
});
