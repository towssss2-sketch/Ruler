import { randomUUID } from 'node:crypto';
import { Account, installFixture, login, register, repository, request } from '../auth/fixture';
import { newCase } from '../case/fixture';

installFixture();
let account: Account; let access: string; let caseId: string;
beforeEach(async (): Promise<void> => {
  account = await register(); access = (await login(account)).accessToken; caseId = await newCase(access);
});

describe('常规任务真实 HTTP CRUD', (): void => {
  it('新建→列表→完成重试→重新打开→清空→删除，描述密文存储且审计无内容', async (): Promise<void> => {
    const response = await request(`/cases/${caseId}/tasks`, { title: '虚构工作', description: 'fictional-task-private', dueDate: '2028-02-29' }, access);
    expect(response.status).toBe(201); const id = response.data.id as string;
    expect(response.data).toMatchObject({ source: 'MANUAL', status: 'TODO', completedAt: null, description: 'fictional-task-private' });
    const record = await repository.db.task.findUniqueOrThrow({ where: { id } });
    expect(Buffer.from(record.description!).includes(Buffer.from('fictional-task-private'))).toBe(false);
    expect((await request(`/cases/${caseId}/tasks?status=TODO&source=MANUAL`, undefined, access)).data.total).toBe(1);
    const done = await request(`/tasks/${id}`, { status: 'DONE' }, access, 'PATCH');
    expect(done.status).toBe(200); expect(typeof done.data.completedAt).toBe('string');
    const retry = await request(`/tasks/${id}`, { status: 'DONE' }, access, 'PATCH');
    expect(retry.data.completedAt).toBe(done.data.completedAt);
    const reopened = await request(`/tasks/${id}`, { status: 'TODO', description: null, dueDate: null }, access, 'PATCH');
    expect(reopened.status).toBe(200); expect(reopened.data).toMatchObject({ completedAt: null, description: null, dueDate: null });
    expect((await request(`/tasks/${id}`, undefined, access, 'DELETE')).status).toBe(200);
    expect((await request(`/cases/${caseId}/tasks`, undefined, access)).data.total).toBe(0);
    expect((await request(`/tasks/${id}`, { title: '不能复活' }, access, 'PATCH')).status).toBe(403);
    const logs = await repository.db.auditLog.findMany({ where: { resourceId: id } });
    expect(logs).toHaveLength(5); expect(JSON.stringify(logs).includes('fictional-task-private')).toBe(false);
  });
  it('可创建已完成任务、更新标题和可见性，分页与状态过滤正确', async (): Promise<void> => {
    const created = await request(`/cases/${caseId}/tasks`, { title: '虚构已完成', status: 'DONE', isClientVisible: true }, access);
    expect(created.status).toBe(201); const id = created.data.id as string;
    expect((await request(`/tasks/${id}`, { title: '虚构新标题', description: '虚构新描述', dueDate: '2026-12-01', isClientVisible: false }, access, 'PATCH')).status).toBe(200);
    expect((await request(`/cases/${caseId}/tasks?status=TODO`, undefined, access)).data.total).toBe(0);
    const page = await request(`/cases/${caseId}/tasks?status=DONE&pageSize=1`, undefined, access);
    expect(page.data.items).toHaveLength(1); expect(page.data.total).toBe(1);
  });
});

describe('任务权限与法定期间保护', (): void => {
  it('未登录、他人、协作成员和已删除案件均无法操作任务', async (): Promise<void> => {
    const created = await request(`/cases/${caseId}/tasks`, { title: '虚构' }, access); const id = created.data.id as string;
    expect((await request(`/tasks/${id}`, { status: 'DONE' }, undefined, 'PATCH')).status).toBe(401);
    const other = await register(); const token = (await login(other)).accessToken;
    await repository.db.caseMember.create({ data: { caseId, userId: other.id, invitedBy: account.id, role: 'EDITOR',
      status: 'ACCEPTED', acceptedAt: new Date() } });
    expect((await request(`/tasks/${id}`, { status: 'DONE' }, token, 'PATCH')).status).toBe(403);
    expect((await request(`/tasks/${id}`, undefined, token, 'DELETE')).status).toBe(403);
    expect((await request(`/cases/${caseId}/tasks`, undefined, token)).status).toBe(403);
    expect((await request(`/tasks/${randomUUID()}`, undefined, access, 'DELETE')).status).toBe(403);
    expect((await request(`/cases/${caseId}`, undefined, access, 'DELETE')).status).toBe(200);
    expect((await request(`/cases/${caseId}/tasks`, { title: '禁止' }, access)).status).toBe(403);
  });
  it('拒绝无效日期、空更新、来源伪造、确认字段和非布尔值', async (): Promise<void> => {
    for (const change of [{ dueDate: '2026-02-29' }, { source: 'DEADLINE_RULE' }, { deadlineConfirmedAt: new Date() },
      { completedAt: new Date() }, { isClientVisible: 'true' }, { title: null }]) {
      expect((await request(`/cases/${caseId}/tasks`, { title: '虚构', ...change }, access)).status).toBe(400);
    }
    const created = await request(`/cases/${caseId}/tasks`, { title: '虚构' }, access);
    expect((await request(`/tasks/${created.data.id as string}`, {}, access, 'PATCH')).status).toBe(400);
    expect((await request(`/cases/${caseId}/tasks?status=INVALID`, undefined, access)).status).toBe(400);
  });
  it('法定期间禁止删除和普通编辑，只可完成或恢复待办，不改变确认数据', async (): Promise<void> => {
    const record = await repository.db.task.create({ data: { caseId, title: '虚构未确认期间', source: 'DEADLINE_RULE',
      deadlineType: 'OTHER', baseDate: new Date('2026-10-16'), proposedDueDate: new Date('2026-10-20') } });
    expect((await request(`/tasks/${record.id}`, undefined, access, 'DELETE')).status).toBe(409);
    expect((await request(`/tasks/${record.id}`, { dueDate: '2026-10-20' }, access, 'PATCH')).status).toBe(409);
    expect((await request(`/tasks/${record.id}`, { title: '修改' }, access, 'PATCH')).status).toBe(409);
    expect((await request(`/tasks/${record.id}`, { status: 'DONE' }, access, 'PATCH')).status).toBe(200);
    expect((await request(`/tasks/${record.id}`, undefined, access, 'DELETE')).status).toBe(409);
    expect((await request(`/tasks/${record.id}`, { status: 'TODO' }, access, 'PATCH')).status).toBe(200);
    const after = await repository.db.task.findUniqueOrThrow({ where: { id: record.id } });
    expect(after.dueDate).toBeNull(); expect(after.deadlineConfirmedAt).toBeNull();
  });
});
