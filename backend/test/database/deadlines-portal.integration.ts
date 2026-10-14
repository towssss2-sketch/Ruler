import { randomBytes } from 'node:crypto';
import { client, createCase, createUser } from './fixtures';

afterAll(async (): Promise<void> => { await client.$disconnect(); });

describe('法定期间确认边界', (): void => {
  it('未确认的规则任务只能存候选日期，不能写入确定截止日', async (): Promise<void> => {
    const caseRecord = await createCase(await createUser());
    const data = { caseId: caseRecord.id, title: '虚构期间待确认', source: 'DEADLINE_RULE' as const,
      deadlineType: 'APPEAL_PERIOD' as const, baseDate: new Date('2026-10-14'), proposedDueDate: new Date('2026-10-29') };
    const pending = await client.task.create({ data });
    expect(pending.dueDate).toBeNull();
    await expect(client.task.update({ where: { id: pending.id }, data: { source: 'MANUAL' } })).rejects.toThrow();
    await expect(client.task.update({ where: { id: pending.id }, data: { dueDate: data.proposedDueDate } })).rejects.toThrow();
    const confirmed = await client.task.update({ where: { id: pending.id }, data: { dueDate: data.proposedDueDate,
      deadlineConfirmedAt: new Date(), deadlineConfirmedById: caseRecord.ownerId, deadlineRuleVersion: 'fictional-rule-v1' } });
    expect(confirmed.deadlineConfirmedById).toBe(caseRecord.ownerId);
    expect(confirmed.dueDate).toEqual(data.proposedDueDate);
  });
  it('不能通过改成 MANUAL 绕过法定期间确认元数据', async (): Promise<void> => {
    const caseRecord = await createCase(await createUser());
    await expect(client.task.create({ data: { caseId: caseRecord.id, title: '虚构未确认期间', source: 'MANUAL',
      deadlineType: 'APPEAL_PERIOD', dueDate: new Date('2026-10-29') } })).rejects.toThrow();
  });
  it('普通手动任务可有日期，但完成状态必须有完成时间', async (): Promise<void> => {
    const caseRecord = await createCase(await createUser());
    const task = await client.task.create({ data: { caseId: caseRecord.id, title: '虚构普通任务',
      dueDate: new Date('2026-10-20') } });
    expect(task.source).toBe('MANUAL');
    expect(task.isClientVisible).toBe(false);
    await expect(client.task.update({ where: { id: task.id }, data: { status: 'DONE' } })).rejects.toThrow();
    expect((await client.task.update({ where: { id: task.id }, data: { status: 'DONE', completedAt: new Date() } })).status).toBe('DONE');
  });
});

describe('所属资源不能通过更新重新绑定', (): void => {
  it('修改当事人所属案件不能自动扩大门户令牌的授权范围', async (): Promise<void> => {
    const user = await createUser();
    const a = await createCase(user);
    const b = await createCase(user);
    const party = await client.caseParty.create({ data: { caseId: a.id, name: '虚构当事人', role: 'PLAINTIFF' } });
    const access = await client.clientAccess.create({ data: { caseId: a.id, casePartyId: party.id,
      grantedBy: user.id, tokenHash: randomBytes(32), expiresAt: new Date(Date.now() + 86400000) } });
    await expect(client.caseParty.update({ where: { id: party.id }, data: { caseId: b.id } })).rejects.toThrow();
    await expect(client.clientAccess.update({ where: { id: access.id }, data: { caseId: b.id } })).rejects.toThrow();
    expect((await client.clientAccess.findUniqueOrThrow({ where: { id: access.id } })).caseId).toBe(a.id);
  });
});

describe('客户门户预留与不可篡改审计', (): void => {
  it('客户访问只存摘要、默认待启用，不能跨案关联当事人', async (): Promise<void> => {
    const user = await createUser();
    const a = await createCase(user);
    const b = await createCase(user);
    const party = await client.caseParty.create({ data: { caseId: a.id, name: '虚构当事人', role: 'PLAINTIFF' } });
    const data = { caseId: a.id, casePartyId: party.id, grantedBy: user.id, tokenHash: randomBytes(32),
      expiresAt: new Date(Date.now() + 86400000) };
    const access = await client.clientAccess.create({ data });
    expect(access.status).toBe('PENDING');
    await expect(client.clientAccess.create({ data: { ...data, caseId: b.id, tokenHash: randomBytes(32) } }))
      .rejects.toMatchObject({ code: 'P2003' });
    await expect(client.clientAccess.create({ data: { ...data, tokenHash: new Uint8Array(10) } })).rejects.toThrow();
    const log = await client.clientAccessLog.create({ data: { clientAccessId: access.id, caseId: a.id,
      action: 'FICTIONAL_READ', resourceType: 'Case', resourceId: a.id, succeeded: true } });
    await expect(client.clientAccessLog.update({ where: { id: log.id }, data: { succeeded: false } })).rejects.toThrow();
    await expect(client.clientAccessLog.delete({ where: { id: log.id } })).rejects.toThrow();
  });
  it('审计日志不可修改、软删除或物理删除', async (): Promise<void> => {
    const user = await createUser();
    const log = await client.auditLog.create({ data: { userId: user.id, action: 'FICTIONAL_TEST', resourceType: 'User', resourceId: user.id } });
    await expect(client.auditLog.update({ where: { id: log.id }, data: { action: 'FICTIONAL_CHANGED' } })).rejects.toThrow();
    await expect(client.auditLog.update({ where: { id: log.id }, data: { deletedAt: new Date() } })).rejects.toThrow();
    await expect(client.auditLog.delete({ where: { id: log.id } })).rejects.toThrow();
    expect((await client.auditLog.findUniqueOrThrow({ where: { id: log.id } })).action).toBe('FICTIONAL_TEST');
  });
  it('送达规则默认人工/禁用，不接入真实法院', async (): Promise<void> => {
    const rule = await client.deliveryPlatformRule.create({ data: { domain: `fictional-${Date.now()}.example.invalid`, platformName: '虚构测试平台' } });
    expect(rule.mode).toBe('MANUAL');
    expect(rule.enabled).toBe(false);
  });
});
