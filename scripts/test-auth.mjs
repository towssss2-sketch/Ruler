import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync } from 'node:fs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const backend = resolve(root, 'backend');
const url = new URL(process.env.DATABASE_URL);
assert.ok(['development', 'test'].includes(process.env.NODE_ENV));
assert.ok(['127.0.0.1', 'localhost'].includes(url.hostname));
assert.equal(url.port, '5432');
assert.equal(url.pathname, '/ruler_dev');
assert.equal(process.env.POSTGRES_DB, 'ruler_dev');
const id = randomUUID().replaceAll('-', '');
const schema = `ruler_auth_${id}`;
const prefix = `ruler:auth:test:${id}:`;
url.searchParams.set('schema', schema);
const environment = { ...process.env, NODE_ENV: 'test', DATABASE_URL: url.toString(), AUTH_REDIS_PREFIX: prefix };
mkdirSync(resolve(root, 'test-results'), { recursive: true });

function run(command, args, input, env = environment) {
  const result = spawnSync(command, args, { cwd: backend, env, input, stdio: input ? ['pipe', 'inherit', 'inherit'] : 'inherit' });
  if (result.error || result.status !== 0) throw new Error('鉴权检查失败；请查看已脱敏测试日志');
}
function ddl(statement) {
  assert.match(schema, /^ruler_auth_[a-f0-9]{32}$/);
  run('docker', ['compose', '--project-directory', root, 'exec', '-T', 'postgres', 'psql', '-X', '-v', 'ON_ERROR_STOP=1',
    '-U', process.env.POSTGRES_USER, '-d', process.env.POSTGRES_DB, '-v', `owned_schema=${schema}`], statement);
}

let created = false;
try {
  ddl('CREATE SCHEMA :"owned_schema";\n');
  created = true;
  run(process.execPath, [resolve(backend, 'node_modules/prisma/build/index.js'), 'migrate', 'deploy']);
  run(process.execPath, [resolve(backend, 'node_modules/jest/bin/jest.js'), '--config', 'jest.auth.cjs', '--runInBand',
    '--json', `--outputFile=${resolve(root, 'test-results/auth-validation.json')}`]);
  run(process.execPath, [resolve(root, 'scripts/render-auth-report.mjs')]);
  run(process.execPath, [resolve(root, 'scripts/render-case-report.mjs')]);
  run(process.execPath, [resolve(root, 'scripts/render-storage-report.mjs')]);
  run(process.execPath, [resolve(root, 'scripts/render-document-report.mjs')]);
} finally {
  // Jest 测试负责清理本次专属 Redis 前缀；不清空 Redis 或任何现有 schema。
  if (created) ddl('SET client_min_messages TO WARNING; DROP SCHEMA :"owned_schema" CASCADE;\n');
}
