import { randomBytes, randomUUID } from 'node:crypto';
import { client, createUser, cipher } from './fixtures';
afterAll(async (): Promise<void> => { await client.$disconnect(); });

async function fixture(): Promise<{ userId: string; ingestionId: string; startedAt: Date; finishedAt: Date; leaseExpiresAt: Date }> {
  const owner = await createUser(), id = randomUUID(), now = new Date();
  await client.ingestionRecord.create({ data: { id, userId: owner.id, channel: 'WECHAT', contentHash: randomBytes(32).toString('hex'),
    rawContent: cipher.encrypt('虚构分类约束', `IngestionRecord:${id}:rawContent`),
    file: { create: { fileName: '虚构.pdf', mimeType: 'application/pdf', sizeBytes: 1, storageKey: `fixture/${id}` } } } });
  return { userId: owner.id, ingestionId: id, startedAt: now, finishedAt: now, leaseExpiresAt: new Date(now.getTime() + 120000) };
}

it('分类必须在成功记录上完整保存，NULL/不明版本/原因及类别冲突不能绕过约束', async (): Promise<void> => {
  const data = { ...await fixture(), status: 'SUCCEEDED' as const };
  for (const change of [
    { classificationCategory: 'PLEADING' as const }, { classificationReason: 'NO_TITLE' },
    { classificationRuleVersion: 'title-v1' },
    { classificationRuleVersion: 'title-v1', classificationReason: 'TITLE_MATCH' },
    { classificationRuleVersion: 'title-v1', classificationReason: 'unknown' },
    { classificationRuleVersion: 'title-v2', classificationReason: 'NO_TITLE' },
    { classificationRuleVersion: 'title-v1', classificationReason: 'NO_TITLE', classificationCategory: 'OTHER' as const },
    { status: 'RUNNING' as const, finishedAt: null, classificationRuleVersion: 'title-v1', classificationReason: 'NO_TITLE' },
    { status: 'MANUAL_REQUIRED' as const, reason: 'TIMEOUT', classificationRuleVersion: 'title-v1', classificationReason: 'NO_TITLE' },
  ]) await expect(client.ingestionPreviewAttempt.create({ data: { ...data, ...change } })).rejects.toThrow();
  await expect(client.ingestionPreviewAttempt.create({ data: { ...data, classificationRuleVersion: 'title-v1',
    classificationReason: 'TITLE_MATCH', classificationCategory: 'PLEADING' } })).resolves.toMatchObject({ classificationCategory: 'PLEADING' });
});

it('空分类和标题冲突是已记录结果，旧成功三列全空仍可读取', async (): Promise<void> => {
  const data = { ...await fixture(), status: 'SUCCEEDED' as const };
  for (const reason of ['NO_TITLE', 'CONFLICTING_TITLES']) {
    await expect(client.ingestionPreviewAttempt.create({ data: { ...data, classificationRuleVersion: 'title-v1', classificationReason: reason } }))
      .resolves.toMatchObject({ classificationCategory: null, classificationReason: reason });
  }
  await expect(client.ingestionPreviewAttempt.create({ data })).resolves.toMatchObject({
    classificationCategory: null, classificationReason: null, classificationRuleVersion: null });
});

it('结束后分类不可篡改/删除，旧成功记录不能伪造回填分类', async (): Promise<void> => {
  const data = { ...await fixture(), status: 'SUCCEEDED' as const };
  const row = await client.ingestionPreviewAttempt.create({ data: { ...data, classificationRuleVersion: 'title-v1',
    classificationReason: 'TITLE_MATCH', classificationCategory: 'DEFENSE' } });
  for (const change of [{ classificationCategory: 'OTHER' as const },
    { classificationCategory: null, classificationReason: null, classificationRuleVersion: null }]) {
    await expect(client.ingestionPreviewAttempt.update({ where: { id: row.id }, data: change })).rejects.toThrow();
  }
  await expect(client.ingestionPreviewAttempt.delete({ where: { id: row.id } })).rejects.toThrow();
  const old = await client.ingestionPreviewAttempt.create({ data });
  await expect(client.ingestionPreviewAttempt.update({ where: { id: old.id }, data: {
    classificationRuleVersion: 'title-v1', classificationReason: 'NO_TITLE' } })).rejects.toThrow();
});
