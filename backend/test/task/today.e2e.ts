import { Account, installFixture, login, register, repository, request } from '../auth/fixture';
import { newCase } from '../case/fixture';
import { calendarDate } from '../../src/modules/task/task-input';
import { todayDate } from '../../src/modules/task/task-policy';

installFixture();
let account: Account; let access: string; let caseId: string;
beforeEach(async (): Promise<void> => {
  account = await register(); access = (await login(account)).accessToken; caseId = await newCase(access);
});

describe('今日汇总真实 HTTP 与数据库', (): void => {
  it('只返回本人待办、逾期及已确认期间窗口，优先级与分页正确，不泄露他案', async (): Promise<void> => {
    const today = todayDate(new Date());
    const offset = (days: number): Date => new Date(today.getTime() + days * 86400000);
    const secondCase = await newCase(access);
    const normal = await repository.db.task.create({ data: { caseId, title: '虚构今日', dueDate: today } });
    const overdue = await repository.db.task.create({ data: { caseId: secondCase, title: '虚构逾期', dueDate: offset(-1) } });
    const deadline = await repository.db.task.create({ data: { caseId, title: '虚构已确认期间测试记录', source: 'DEADLINE_RULE',
      deadlineType: 'OTHER', baseDate: offset(-2), dueDate: offset(7), deadlineConfirmedAt: new Date(),
      deadlineConfirmedById: account.id, deadlineRuleVersion: 'fictional-test-fixture', alertDays: [7,3,1] } });
    await repository.db.task.createMany({ data: [
      { caseId, title: '虚构未来', dueDate: offset(1) }, { caseId, title: '虚构无日期' },
      { caseId, title: '虚构已完成', status: 'DONE', completedAt: new Date(), dueDate: today },
      { caseId, title: '虚构已删除', deletedAt: new Date(), dueDate: today },
      { caseId, title: '虚构未确认', source: 'DEADLINE_RULE', deadlineType: 'OTHER', baseDate: today, proposedDueDate: today },
      { caseId, title: '虚构窗口外', source: 'DEADLINE_RULE', deadlineType: 'OTHER', baseDate: today, dueDate: offset(8),
        deadlineConfirmedAt: new Date(), deadlineConfirmedById: account.id, deadlineRuleVersion: 'fictional-test-fixture' },
    ] });
    const other = await register(); const token = (await login(other)).accessToken; const foreignCase = await newCase(token);
    await repository.db.task.create({ data: { caseId: foreignCase, title: '不能看到', dueDate: today } });
    const response = await request('/tasks/today?pageSize=2', undefined, access);
    expect(response.status).toBe(200); expect(response.data).toMatchObject({ total: 3, timeZone: 'Asia/Shanghai', date: today.toISOString().slice(0,10) });
    expect((response.data.items as { id: string }[]).map((item): string => item.id)).toEqual([deadline.id, overdue.id]);
    const parents = await repository.db.case.findMany({ where: { id: { in: [caseId, secondCase] } } });
    for (const item of response.data.items as Record<string, unknown>[]) {
      const parent = parents.find((record): boolean => record.id === item.caseId);
      expect(parent).toBeDefined(); expect(item.caseNo).toBe(parent?.caseNo); expect(item.court).toBe(parent?.court);
      expect(item.case).toBeUndefined(); expect(item.clerkPhone).toBeUndefined(); expect(item.parties).toBeUndefined();
    }
    const second = await request('/tasks/today?pageSize=2&page=2', undefined, access);
    expect((second.data.items as { id: string }[]).map((item): string => item.id)).toEqual([normal.id]);
    expect(response.raw.includes('不能看到')).toBe(false);
  });
  it('案件删除立即从汇总移除；未知参数拒绝，未登录返回 401', async (): Promise<void> => {
    const date = todayDate(new Date()).toISOString().slice(0,10);
    await request(`/cases/${caseId}/tasks`, { title: '虚构今日', dueDate: date }, access);
    expect((await request('/tasks/today',undefined,access)).data.total).toBe(1);
    await request(`/cases/${caseId}`,undefined,access,'DELETE');
    expect((await request('/tasks/today',undefined,access)).data.total).toBe(0);
    expect((await request('/tasks/today?userId=other',undefined,access)).status).toBe(400);
    expect((await request('/tasks/today')).status).toBe(401);
    expect(calendarDate(date).toISOString().slice(0,10)).toBe(date);
  });
});
