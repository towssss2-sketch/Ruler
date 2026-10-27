import { randomBytes, randomUUID } from 'node:crypto';
import { client, createUser, cipher } from './fixtures';
afterAll(async (): Promise<void> => { await client.$disconnect(); });

async function fixture(): Promise<{ userId: string; ingestionId: string; startedAt: Date; leaseExpiresAt: Date }> {
  const user = await createUser(), id = randomUUID();
  await client.ingestionRecord.create({ data: { id, userId: user.id, channel: 'WECHAT', contentHash: randomBytes(32).toString('hex'),
    rawContent: cipher.encrypt('虚构记录约束', `IngestionRecord:${id}:rawContent`),
    file: { create: { fileName: '虚构.pdf', mimeType: 'application/pdf', sizeBytes: 1, storageKey: `fixture/${id}` } } } });
  return { userId: user.id, ingestionId: id, startedAt: new Date(), leaseExpiresAt: new Date(Date.now() + 120000) };
}

it('提取记录必须对应同用户附件，每用户最多一个运行中尝试', async (): Promise<void> => {
  const a = await fixture(), b = await fixture();
  await expect(client.ingestionPreviewAttempt.create({ data: { ...a, userId: b.userId } })).rejects.toThrow();
  await expect(client.ingestionPreviewAttempt.create({ data: { ...a, ingestionId: randomUUID() } })).rejects.toThrow();
  const row = await client.ingestionPreviewAttempt.create({ data: a });
  await expect(client.ingestionPreviewAttempt.create({ data: a })).rejects.toThrow();
  await client.ingestionPreviewAttempt.update({ where: { id: row.id }, data: { status: 'SUCCEEDED', finishedAt: a.startedAt } });
  await expect(client.ingestionPreviewAttempt.create({ data: a })).resolves.toMatchObject({ status: 'RUNNING' });
});

it('提取结果的时间/固定原因/状态组合受数据库约束，拒绝空值绕过', async (): Promise<void> => {
  const data = await fixture();
  for (const change of [
    { leaseExpiresAt: data.startedAt }, { status: 'RUNNING' as const, reason: 'TIMEOUT' },
    { status: 'SUCCEEDED' as const }, { status: 'SUCCEEDED' as const, finishedAt: data.leaseExpiresAt },
    { status: 'MANUAL_REQUIRED' as const, finishedAt: data.startedAt },
    { status: 'MANUAL_REQUIRED' as const, reason: 'unknown', finishedAt: data.startedAt },
    { status: 'INTERRUPTED' as const }, { status: 'INTERRUPTED' as const, finishedAt: data.startedAt },
    { status: 'MANUAL_REQUIRED' as const, reason: 'TIMEOUT', finishedAt: new Date(0) },
  ]) await expect(client.ingestionPreviewAttempt.create({ data: { ...data, ...change } })).rejects.toThrow();
  await expect(client.ingestionPreviewAttempt.create({ data: { ...data, status: 'INTERRUPTED', finishedAt: data.leaseExpiresAt } })).resolves.toMatchObject({ status: 'INTERRUPTED' });
});

it('记录身份与期限不可改，终态不可覆写/删除，旧失败保留', async (): Promise<void> => {
  const data = await fixture(), row = await client.ingestionPreviewAttempt.create({ data: await fixture() });
  for (const change of [{ id: randomUUID() }, { userId: data.userId }, { ingestionId: data.ingestionId },
    { startedAt: new Date(0) }, { leaseExpiresAt: new Date(Date.now() + 600000) }]) {
    await expect(client.ingestionPreviewAttempt.update({ where: { id: row.id }, data: change })).rejects.toThrow();
  }
  await client.ingestionPreviewAttempt.update({ where: { id: row.id }, data: { status: 'MANUAL_REQUIRED', reason: 'TIMEOUT', finishedAt: new Date() } });
  await expect(client.ingestionPreviewAttempt.update({ where: { id: row.id }, data: { status: 'RUNNING', reason: null, finishedAt: null } })).rejects.toThrow();
  await expect(client.ingestionPreviewAttempt.delete({ where: { id: row.id } })).rejects.toThrow();
  expect((await client.ingestionPreviewAttempt.findUniqueOrThrow({ where: { id: row.id } })).reason).toBe('TIMEOUT');
});
