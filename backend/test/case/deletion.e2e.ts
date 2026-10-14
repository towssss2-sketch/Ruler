import { randomUUID } from 'node:crypto';
import { app, installFixture, login, register, repository, request } from '../auth/fixture';
import { EncryptionService } from '../../src/encryption.service';
import { input, newCase } from './fixture';
import { linkedRecords } from './delete-fixture';
import * as transaction from '../../src/modules/case/case-transaction';

installFixture();

describe('详情统计与案件级联软删除', (): void => {
  it('文件只统计活跃当前版本，任务只统计未完成；删除归档全部关联记录并保留日志', async (): Promise<void> => {
    const owner = await register();
    const { accessToken } = await login(owner);
    const values = input();
    const id = await newCase(accessToken, values);
    const { accessId } = await linkedRecords(owner.id, id);
    const before = await request(`/cases/${id}`, undefined, accessToken);
    expect(before.data).toMatchObject({ documentCount: 1, pendingTaskCount: 1 });
    expect((await request(`/cases/${id}`, undefined, accessToken, 'DELETE')).status).toBe(200);
    expect((await request(`/cases/${id}`, undefined, accessToken)).status).toBe(403);
    expect((await request(`/cases/${id}`, undefined, accessToken, 'DELETE')).status).toBe(403);
    expect((await request('/cases', undefined, accessToken)).data.total).toBe(0);
    const where = { caseId: id, deletedAt: null };
    const db = repository.db;
    expect(await db.caseParty.count({ where })).toBe(0);
    expect(await db.caseMember.count({ where })).toBe(0);
    expect(await db.document.count({ where })).toBe(0);
    expect(await db.task.count({ where })).toBe(0);
    expect(await db.timelineEvent.count({ where })).toBe(0);
    expect(await db.caseAnalysis.count({ where })).toBe(0);
    expect(await db.documentDraft.count({ where })).toBe(0);
    expect(await db.ingestionRecord.count({ where: { matchedCaseId: id, deletedAt: null } })).toBe(0);
    const access = await db.clientAccess.findUniqueOrThrow({ where: { id: accessId } });
    expect(access.status).toBe('REVOKED');
    expect(access.revokedAt).not.toBeNull();
    expect(await db.clientAccessLog.count({ where })).toBe(1);
    expect(await db.auditLog.count({ where })).toBe(2);
    expect(await db.document.count({ where: { caseId: id } })).toBe(3);
    expect((await request('/cases', values, accessToken)).status).toBe(201);
  });
  it('删除审计失败时整个关联图回滚，文件、权限、案件仍可用', async (): Promise<void> => {
    const owner = await register();
    const { accessToken } = await login(owner);
    const id = await newCase(accessToken);
    const { accessId } = await linkedRecords(owner.id, id);
    const fault = jest.spyOn(transaction, 'auditCase').mockRejectedValueOnce(new Error('fictional-audit-failure'));
    try { expect((await request(`/cases/${id}`, undefined, accessToken, 'DELETE')).status).toBe(500); }
    finally { fault.mockRestore(); }
    expect((await request(`/cases/${id}`, undefined, accessToken)).status).toBe(200);
    expect(await repository.db.document.count({ where: { caseId: id, deletedAt: null } })).toBe(2);
    expect((await repository.db.clientAccess.findUniqueOrThrow({ where: { id: accessId } })).status).toBe('ACTIVE');
    expect(await repository.db.auditLog.count({ where: { caseId: id, action: 'CASE_DELETED' } })).toBe(0);
  });
});

describe('删除边界与当事人访问撤销', (): void => {
  it('存在法定期间记录时拒绝级联删除，普通结案不隐藏记录', async (): Promise<void> => {
    const { accessToken } = await login(await register());
    const id = await newCase(accessToken);
    await repository.db.task.create({ data: { caseId: id, title: '虚构待复核期间', source: 'DEADLINE_RULE',
      deadlineType: 'APPEAL_PERIOD', baseDate: new Date() } });
    const reply = await request(`/cases/${id}`, undefined, accessToken, 'DELETE');
    expect(reply.status).toBe(409);
    expect(reply.raw).toContain('法定期间');
    expect((await request(`/cases/${id}`, { status: 'CLOSED' }, accessToken, 'PATCH')).status).toBe(200);
    expect(await repository.db.task.count({ where: { caseId: id, deletedAt: null } })).toBe(1);
  });
  it('删除不擅自归档其他用户的归集资料，返回明确保护消息', async (): Promise<void> => {
    const owner = await register();
    const other = await register();
    const { accessToken } = await login(owner);
    const id = await newCase(accessToken);
    const { ingestionId } = await linkedRecords(owner.id, id);
    // userId 不可变，创建时选择其他虚构用户；模拟未来协作归集的边界。
    const source = await repository.db.ingestionRecord.findUniqueOrThrow({ where: { id: ingestionId } });
    const otherId = randomUUID();
    await repository.db.ingestionRecord.create({ data: { id: otherId, userId: other.id, matchedCaseId: id, channel: 'SMS',
      status: 'MATCHED', rawContent: app.get(EncryptionService).encrypt('虚构其他用户短信', `IngestionRecord:${otherId}:rawContent`),
      contentHash: source.contentHash } });
    expect((await request(`/cases/${id}`, undefined, accessToken, 'DELETE')).status).toBe(409);
    expect((await request(`/cases/${id}`, undefined, accessToken)).status).toBe(200);
  });
  it('移除当事人立即吊销其预留门户权限，保留访问日志；密文损坏时不返回半份详情', async (): Promise<void> => {
    const owner = await register();
    const { accessToken } = await login(owner);
    const id = await newCase(accessToken);
    const { accessId } = await linkedRecords(owner.id, id);
    expect((await request(`/cases/${id}`, { parties: [{ role: 'PLAINTIFF', name: '新虚构当事人' }] }, accessToken, 'PATCH')).status).toBe(200);
    expect((await repository.db.clientAccess.findUniqueOrThrow({ where: { id: accessId } })).status).toBe('REVOKED');
    expect(await repository.db.clientAccessLog.count({ where: { clientAccessId: accessId } })).toBe(1);
    const record = await repository.db.case.findUniqueOrThrow({ where: { id } });
    const corrupted = Buffer.from(record.notes!);
    corrupted[corrupted.length - 1] = corrupted[corrupted.length - 1]! ^ 1;
    await repository.db.case.update({ where: { id }, data: { notes: corrupted } });
    const reply = await request(`/cases/${id}`, undefined, accessToken);
    expect(reply.status).toBe(500);
    expect(reply.raw.includes('虚构案情')).toBe(false);
  });
});
