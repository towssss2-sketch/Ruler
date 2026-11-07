import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, readdirSync } from 'node:fs';
import { randomUUID, createHash, randomBytes, createCipheriv } from 'node:crypto';
import { resolve } from 'node:path';

const migration = '20261108000000_ingestion_classification_results';

/** 给阶段0升级路径补上真实旧版分类空列前的数据；不改已部署迁移。 */
export function copyPreviousMigrations(backend, target) {
  const root = resolve(backend, 'prisma/migrations');
  for (const name of readdirSync(root)) {
    if (!/^\d{14}_/.test(name) || name >= migration) continue;
    mkdirSync(resolve(target, 'migrations', name), { recursive: true });
    copyFileSync(resolve(root, name, 'migration.sql'), resolve(target, 'migrations', name, 'migration.sql'));
  }
}

/** 虚构内容也使用 AES-256-GCM，仅检验密文逐字节保留，不向日志输出。 */
export async function seedPreviousAttempts(client) {
  const userId = randomUUID(), ingestionId = randomUUID(), successful = randomUUID(), running = randomUUID();
  const nonce = randomBytes(12), encrypt = createCipheriv('aes-256-gcm', randomBytes(32), nonce);
  encrypt.setAAD(Buffer.from(`IngestionRecord:${ingestionId}:rawContent`));
  const ciphertext = Buffer.concat([encrypt.update('虚构分类升级材料'), encrypt.final()]);
  const rawContent = Buffer.concat([Buffer.from('GCM1'), nonce, encrypt.getAuthTag(), ciphertext]);
  await client.user.create({ data: { id: userId, email: `upgrade-${userId}@example.invalid`, name: '虚构升级律师', passwordHash: 'TEST_ONLY_HASH' } });
  await client.ingestionRecord.create({ data: { id: ingestionId, userId, channel: 'WECHAT', rawContent,
    contentHash: createHash('sha256').update(rawContent).digest('hex'), file: { create: {
      fileName: '虚构升级.pdf', mimeType: 'application/pdf', sizeBytes: 1, storageKey: `upgrade-fixture/${ingestionId}` } } } });
  await client.$executeRaw`INSERT INTO "IngestionPreviewAttempt"
    (id, "ingestionId", "userId", status, "startedAt", "leaseExpiresAt", "finishedAt") VALUES
    (${successful}::uuid, ${ingestionId}::uuid, ${userId}::uuid, 'SUCCEEDED', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '2 minutes', CURRENT_TIMESTAMP),
    (${running}::uuid, ${ingestionId}::uuid, ${userId}::uuid, 'RUNNING', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '2 minutes', NULL)`;
  const rows = await client.$queryRaw`SELECT * FROM "IngestionPreviewAttempt" WHERE "ingestionId" = ${ingestionId}::uuid ORDER BY id`;
  assert.equal(rows.length, 2);
  assert.equal(Object.hasOwn(rows[0], 'classificationReason'), false);
  return { ingestionId, rawContent, rows };
}

/** 最新迁移与重复部署之后，旧成功/运行记录原字段与密文不变，新增三列均为空。 */
export async function verifyPreviousAttempts(client, fixture) {
  const rows = await client.ingestionPreviewAttempt.findMany({ where: { ingestionId: fixture.ingestionId }, orderBy: { id: 'asc' } });
  assert.equal(rows.length, 2);
  for (let i = 0; i < rows.length; i++) {
    const { classificationCategory, classificationReason, classificationRuleVersion, ...old } = rows[i];
    assert.deepEqual([classificationCategory, classificationReason, classificationRuleVersion], [null, null, null]);
    assert.deepEqual(old, fixture.rows[i]);
  }
  const record = await client.ingestionRecord.findUniqueOrThrow({ where: { id: fixture.ingestionId } });
  assert.deepEqual(Buffer.from(record.rawContent), fixture.rawContent);
  console.log('PASS 阶段6A4A真实旧库升级：成功/运行记录及密文保留，分类不回填，重复部署通过');
}
