import { randomUUID } from 'node:crypto';
import { app, installFixture, login, register, repository, request } from '../auth/fixture';
import { input, newCase } from './fixture';
import { CaseDetail } from '../../src/modules/case/case-view.service';
import { EncryptionService } from '../../src/encryption.service';
import * as transaction from '../../src/modules/case/case-transaction';

installFixture();

describe('案件创建与加密', (): void => {
  it('真实注册登录后新建案件：当事人、OWNER、审计原子保存，敏感信息加密', async (): Promise<void> => {
    const account = await register();
    const { accessToken } = await login(account);
    const values = input();
    const id = await newCase(accessToken, { ...values, caseNo: values.caseNo.replace('(', '（').replace(')', '）') });
    const reply = await request(`/cases/${id}`, undefined, accessToken);
    expect(reply.status).toBe(200);
    const detail = reply.data as unknown as CaseDetail;
    expect(detail.caseNo).toBe(values.caseNo);
    expect(detail.fee).toBe('123456789012.34');
    expect(detail.parties[0]?.phone === 'fictional-phone').toBe(true);
    expect(detail.notes === values.notes).toBe(true);
    const saved = await repository.db.case.findUniqueOrThrow({ where: { id }, include: { parties: true, members: true } });
    expect(saved.members[0]?.userId).toBe(account.id);
    expect(saved.members[0]?.role).toBe('OWNER');
    expect(Buffer.from(saved.parties[0]!.phone!).includes(Buffer.from('fictional-phone'))).toBe(false);
    expect(Buffer.from(saved.notes!).includes(Buffer.from(values.notes!))).toBe(false);
    expect(app.get(EncryptionService).decrypt(saved.notes!, `Case:${id}:notes`) === values.notes).toBe(true);
    const audits = await repository.db.auditLog.findMany({ where: { caseId: id } });
    expect(audits.map((audit): string => audit.action)).toEqual(['CASE_CREATED']);
    expect(JSON.stringify(audits).includes(values.notes!)).toBe(false);
  });
  it('同用户并发重复建案恰好一条成功，409 指向已有案件；其他用户独立建案', async (): Promise<void> => {
    const a = await login(await register());
    const b = await login(await register());
    const values = input();
    const responses = await Promise.all([request('/cases', values, a.accessToken), request('/cases', values, a.accessToken)]);
    expect(responses.map((reply): number => reply.status).sort()).toEqual([201, 409]);
    const id = responses.find((reply): boolean => reply.status === 201)!.data.id;
    expect(responses.find((reply): boolean => reply.status === 409)!.data.existingCaseId).toBe(id);
    expect((await request('/cases', values, b.accessToken)).status).toBe(201);
  });
  it('创建审计故障时连同案件、当事人与 OWNER 全部回滚', async (): Promise<void> => {
    const { accessToken } = await login(await register());
    const values = input();
    const fault = jest.spyOn(transaction, 'auditCase').mockRejectedValueOnce(new Error('fictional-internal-error'));
    try { expect((await request('/cases', values, accessToken)).status).toBe(500); }
    finally { fault.mockRestore(); }
    expect(await repository.db.case.count({ where: { caseNo: values.caseNo } })).toBe(0);
  });
});

describe('案件修改事务', (): void => {
  it('更新保留当事人 id 和未提供敏感字段，省略的当事人归档；新增、清空均生效', async (): Promise<void> => {
    const { accessToken } = await login(await register());
    const id = await newCase(accessToken, input({ parties: [
      { role: 'PLAINTIFF', name: '虚构甲', phone: 'fictional-phone' }, { role: 'DEFENDANT', name: '虚构乙' }] }));
    const before = (await request(`/cases/${id}`, undefined, accessToken)).data as unknown as CaseDetail;
    const kept = before.parties.find((party): boolean => party.name === '虚构甲')!;
    const reply = await request(`/cases/${id}`, { notes: null, fee: null, judge: '虚构审判员',
      stage: 'SECOND_INSTANCE', status: 'CLOSED', feeStatus: 'WAIVED',
      parties: [{ id: kept.id, name: '虚构甲修改', role: 'PLAINTIFF' }, { name: '虚构丙', role: 'THIRD_PARTY' }] }, accessToken, 'PATCH');
    expect(reply.status).toBe(200);
    const after = (await request(`/cases/${id}`, undefined, accessToken)).data as unknown as CaseDetail;
    expect(after.notes).toBeNull();
    expect(after.fee).toBeNull();
    expect(after.stage).toBe('SECOND_INSTANCE');
    expect(after.parties.find((party): boolean => party.id === kept.id)?.phone === 'fictional-phone').toBe(true);
    expect(after.parties).toHaveLength(2);
    expect(await repository.db.caseParty.count({ where: { caseId: id, deletedAt: { not: null } } })).toBe(1);
    expect(await repository.db.auditLog.count({ where: { caseId: id, action: 'CASE_UPDATED' } })).toBe(1);
  });
  it('传入外案当事人 ID 时返回 400，先写入的案由也回滚', async (): Promise<void> => {
    const { accessToken } = await login(await register());
    const id = await newCase(accessToken);
    expect((await request(`/cases/${id}`, { cause: '不应落库', parties: [
      { id: randomUUID(), role: 'PLAINTIFF', name: '虚构当事人' }] }, accessToken, 'PATCH')).status).toBe(400);
    expect((await request(`/cases/${id}`, undefined, accessToken)).data.cause).toBe('虚构合同纠纷');
    expect(await repository.db.auditLog.count({ where: { caseId: id, action: 'CASE_UPDATED' } })).toBe(0);
  });
  it('修改为本用户已有案号返回 409，原案件保持不变', async (): Promise<void> => {
    const { accessToken } = await login(await register());
    const existing = input();
    const target = await newCase(accessToken, existing);
    const id = await newCase(accessToken);
    const reply = await request(`/cases/${id}`, { caseNo: existing.caseNo }, accessToken, 'PATCH');
    expect(reply.status).toBe(409);
    expect(reply.data.existingCaseId).toBe(target);
    expect((await request(`/cases/${id}`, undefined, accessToken)).data.caseNo).not.toBe(existing.caseNo);
  });
});
