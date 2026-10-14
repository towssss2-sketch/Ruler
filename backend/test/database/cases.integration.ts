import { randomUUID } from 'node:crypto';
import { client, createCase, createUser } from './fixtures';

afterAll(async (): Promise<void> => { await client.$disconnect(); });

describe('案件、主办律师与软删除', (): void => {
  it('同一主办律师重复案号+法院被拒绝，不同主办律师可独立建案', async (): Promise<void> => {
    const user = await createUser();
    const caseRecord = await createCase(user);
    await expect(createCase(user, caseRecord.caseNo)).rejects.toMatchObject({ code: 'P2002' });
    const second = await createCase(await createUser(), caseRecord.caseNo);
    expect(second.id).not.toBe(caseRecord.id);
  });
  it('软删除保留历史，允许同一标识的新活跃案件', async (): Promise<void> => {
    const user = await createUser();
    const original = await createCase(user);
    await client.case.update({ where: { id: original.id }, data: { deletedAt: new Date() } });
    const replacement = await createCase(user, original.caseNo);
    expect(replacement.id).not.toBe(original.id);
    expect((await client.case.findUniqueOrThrow({ where: { id: original.id } })).deletedAt).not.toBeNull();
  });
  it('缺少有效 OWNER 的案件不能单独落库', async (): Promise<void> => {
    const user = await createUser();
    const id = randomUUID();
    await expect(client.case.create({ data: {
      id, ownerId: user.id, caseNo: `虚构-${id}`, cause: '虚构案由', court: '虚构法院',
    } })).rejects.toThrow();
    expect(await client.case.findUnique({ where: { id } })).toBeNull();
  });
  it('禁止只改主办律师而不同步 OWNER 成员', async (): Promise<void> => {
    const original = await createCase(await createUser());
    const other = await createUser();
    await expect(client.case.update({ where: { id: original.id }, data: { ownerId: other.id } })).rejects.toThrow();
    expect((await client.case.findUniqueOrThrow({ where: { id: original.id } })).ownerId).toBe(original.ownerId);
  });
  it('同一事务可一致转让主办律师，原 OWNER 降为 EDITOR', async (): Promise<void> => {
    const original = await createCase(await createUser());
    const other = await createUser();
    const member = await client.caseMember.create({ data: { caseId: original.id, userId: other.id,
      invitedBy: original.ownerId, role: 'EDITOR', status: 'ACCEPTED', acceptedAt: new Date() } });
    await client.$transaction([
      client.caseMember.update({ where: { caseId_userId: { caseId: original.id, userId: original.ownerId } }, data: { role: 'EDITOR' } }),
      client.caseMember.update({ where: { id: member.id }, data: { role: 'OWNER' } }),
      client.case.update({ where: { id: original.id }, data: { ownerId: other.id } }),
    ]);
    expect((await client.case.findUniqueOrThrow({ where: { id: original.id } })).ownerId).toBe(other.id);
  });
  it('重复协作成员被拒绝，撤销保留原接受日期', async (): Promise<void> => {
    const original = await createCase(await createUser());
    const other = await createUser();
    const acceptedAt = new Date();
    const member = await client.caseMember.create({ data: { caseId: original.id, userId: other.id,
      invitedBy: original.ownerId, status: 'ACCEPTED', acceptedAt } });
    await expect(client.caseMember.create({ data: { caseId: original.id, userId: other.id,
      invitedBy: original.ownerId } })).rejects.toMatchObject({ code: 'P2002' });
    const revoked = await client.caseMember.update({ where: { id: member.id }, data: { status: 'REVOKED' } });
    expect(revoked.acceptedAt).toEqual(acceptedAt);
  });
});

describe('身份与容量元数据', (): void => {
  it('不允许改 UUID，避免密文上下文和关联身份错绑', async (): Promise<void> => {
    const user = await createUser();
    await expect(client.user.update({ where: { id: user.id }, data: { id: randomUUID() } })).rejects.toThrow();
    expect(await client.user.findUnique({ where: { id: user.id } })).not.toBeNull();
  });
  it('配额和使用量不能负数，但保留会员降级后的超额只读状态', async (): Promise<void> => {
    const user = await createUser();
    await expect(client.user.update({ where: { id: user.id }, data: { storageUsedBytes: -1n } })).rejects.toThrow();
    const overQuota = await client.user.update({ where: { id: user.id }, data: { storageQuotaBytes: 100n, storageUsedBytes: 200n } });
    expect(overQuota.storageUsedBytes).toBeGreaterThan(overQuota.storageQuotaBytes);
  });
  it('金额必须有限且非负，不接受 NaN', async (): Promise<void> => {
    const original = await createCase(await createUser());
    await expect(client.case.update({ where: { id: original.id }, data: { fee: '-1' } })).rejects.toThrow();
    await expect(client.case.update({ where: { id: original.id }, data: { fee: 'NaN' } })).rejects.toThrow();
  });
});
