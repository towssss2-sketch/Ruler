import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, rmSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const backend = resolve(root, 'backend');
const require = createRequire(resolve(backend, 'package.json'));
const { PrismaClient } = require('@prisma/client');
const baseUrl = new URL(process.env.DATABASE_URL);
assert.ok(['development', 'test'].includes(process.env.NODE_ENV), '仅允许虚构开发环境');
assert.ok(['127.0.0.1', 'localhost'].includes(baseUrl.hostname), '不得在远程或生产数据库运行');
assert.equal(baseUrl.pathname, '/ruler_dev', '仅允许明确的 ruler_dev 开发库');
assert.equal(baseUrl.port, '5432', '仅允许当前 Compose 的开发数据库端口');
assert.equal(process.env.POSTGRES_DB, 'ruler_dev', '测试 DDL 只能在 ruler_dev 内执行');
assert.ok(process.env.POSTGRES_USER && process.env.POSTGRES_DB, '缺少开发数据库变量');
const runId = randomUUID().replaceAll('-', '');
const fresh = `ruler_phase1_fresh_${runId}`;
const upgrade = `ruler_phase1_upgrade_${runId}`;
const created = [];
mkdirSync(resolve(backend, 'test-results'), { recursive: true });
const oldRoot = mkdtempSync(resolve(backend, 'test-results/stage0-migration-'));
mkdirSync(resolve(root, 'test-results'), { recursive: true });

function run(command, args, env = process.env, input) {
  const result = spawnSync(command, args, { cwd: backend, env, input, stdio: input ? ['pipe', 'inherit', 'inherit'] : 'inherit' });
  if (result.error) throw new Error('数据库验证子进程无法启动');
  if (result.status !== 0) throw new Error(`数据库验证子进程失败，退出码 ${result.status}`);
}
function schemaUrl(schema) {
  const url = new URL(baseUrl);
  url.searchParams.set('schema', schema);
  return url.toString();
}
function ddl(schema, sql) {
  assert.match(schema, /^ruler_phase1_(fresh|upgrade)_[a-f0-9]{32}$/);
  run('docker', ['compose', '--project-directory', root, 'exec', '-T', 'postgres', 'psql',
    '-X', '-v', 'ON_ERROR_STOP=1', '-U', process.env.POSTGRES_USER, '-d', process.env.POSTGRES_DB,
    '-v', `test_schema=${schema}`], process.env, sql);
}
function migrate(schema, path, config) {
  const args = [resolve(backend, 'node_modules/prisma/build/index.js'), 'migrate', 'deploy', '--schema', path];
  if (config) args.push('--config', config);
  run(process.execPath, args,
    { ...process.env, DATABASE_URL: schemaUrl(schema) });
}

try {
  for (const schema of [fresh, upgrade]) {
    ddl(schema, 'CREATE SCHEMA :"test_schema";\n');
    created.push(schema);
  }
  // 先部署仓库中保持不变的阶段 0 迁移，再验证向前升级；不重置现有开发数据。
  writeFileSync(resolve(oldRoot, 'schema.prisma'), `generator client {
  provider = "prisma-client-js"
}
datasource db {
  provider = "postgresql"
  url = env("DATABASE_URL")
}
model EnvironmentProbe {
  id String @id @default(uuid()) @db.Uuid
  label String
  createdAt DateTime @default(now())
}
`);
  mkdirSync(resolve(oldRoot, 'migrations/20261014000000_environment_probe'), { recursive: true });
  copyFileSync(resolve(backend, 'prisma/migrations/20261014000000_environment_probe/migration.sql'),
    resolve(oldRoot, 'migrations/20261014000000_environment_probe/migration.sql'));
  copyFileSync(resolve(backend, 'prisma/migrations/migration_lock.toml'), resolve(oldRoot, 'migrations/migration_lock.toml'));
  writeFileSync(resolve(oldRoot, 'prisma.config.ts'), "import { defineConfig } from 'prisma/config';\nexport default defineConfig({ schema: 'schema.prisma', migrations: { path: 'migrations' } });\n");
  migrate(upgrade, resolve(oldRoot, 'schema.prisma'), resolve(oldRoot, 'prisma.config.ts'));
  const oldClient = new PrismaClient({ datasourceUrl: schemaUrl(upgrade) });
  let probe;
  try {
    const rows = await oldClient.$queryRaw`SELECT count(*)::int AS count FROM "_prisma_migrations" WHERE finished_at IS NOT NULL`;
    assert.equal(rows[0].count, 1, '升级测试必须从实际阶段0开始');
    probe = await oldClient.environmentProbe.create({ data: { label: '阶段0虚构探针保留' } });
  }
  finally { await oldClient.$disconnect(); }
  for (const schema of [fresh, upgrade]) {
    migrate(schema, resolve(backend, 'prisma'));
    migrate(schema, resolve(backend, 'prisma'));
  }
  const upgradedClient = new PrismaClient({ datasourceUrl: schemaUrl(upgrade) });
  try {
    assert.equal((await upgradedClient.environmentProbe.findUniqueOrThrow({ where: { id: probe.id } })).label, '阶段0虚构探针保留');
    await upgradedClient.user.create({ data: { email: `upgrade-${runId}@example.invalid`, name: '升级虚构律师', passwordHash: 'TEST_ONLY_HASH' } });
  } finally { await upgradedClient.$disconnect(); }
  console.log('PASS 空库部署、阶段0升级、原探针数据保留及重复部署（两个独立测试 schema）');
  run(process.execPath, [resolve(backend, 'node_modules/jest/bin/jest.js'), '--config', 'jest.database.cjs',
    '--runInBand', '--json', `--outputFile=${resolve(root, 'test-results/schema-database.json')}`],
    { ...process.env, NODE_ENV: 'test', DATABASE_URL: schemaUrl(fresh) });
} finally {
  for (const schema of created.reverse()) ddl(schema, 'SET client_min_messages TO WARNING; DROP SCHEMA :"test_schema" CASCADE;\n');
  rmSync(oldRoot, { recursive: true, force: true });
}
