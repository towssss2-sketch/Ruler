import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { randomBytes, randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const backend = resolve(root, 'backend');
const require = createRequire(resolve(backend, 'package.json'));
const Redis = require('ioredis');
const database = new URL(process.env.DATABASE_URL);
assert.ok(['development', 'test'].includes(process.env.NODE_ENV));
assert.ok(['127.0.0.1', 'localhost'].includes(database.hostname));
assert.equal(database.pathname, '/ruler_dev');
assert.equal(process.env.POSTGRES_DB, 'ruler_dev');
const id = randomUUID().replaceAll('-', '');
const schema = `ruler_client_${id}`;
const prefix = `ruler:auth:test:${id}:`;
database.searchParams.set('schema', schema);
process.env.DATABASE_URL = database.toString();
process.env.AUTH_REDIS_PREFIX = prefix;
process.env.NODE_ENV = 'test';
const password = randomBytes(32).toString('base64url');
const output = resolve(root, 'test-results');
mkdirSync(output, { recursive: true });

/** 仅操作本次生成的隔离 schema；子进程异常不回显连接串。 */
function run(command, args, input) {
  const result = spawnSync(command, args, { cwd: backend, input, encoding: 'utf8' });
  if (result.error || result.status !== 0) throw new Error('隔离测试准备或清理失败');
}
function ddl(statement) {
  assert.match(schema, /^ruler_client_[a-f0-9]{32}$/);
  run('docker', ['compose', '--project-directory', root, 'exec', '-T', 'postgres', 'psql',
    '-X', '-v', 'ON_ERROR_STOP=1', '-U', process.env.POSTGRES_USER, '-d', process.env.POSTGRES_DB,
    '-v', `owned_schema=${schema}`], statement);
}

/** 验证码仅由同一进程读取，不增加取码接口、固定账号或注册后门。 */
async function account(app, origin, Mailbox) {
  const email = `fictional-${randomUUID()}@example.invalid`;
  const post = (path, data) => fetch(`${origin}${path}`, { method: 'POST',
    headers: { 'content-type': 'application/json' }, body: JSON.stringify(data) });
  assert.equal((await post('/auth/verification-code', { email })).status, 200);
  const code = app.get(Mailbox).take(email);
  assert.equal(typeof code, 'string');
  assert.equal((await post('/auth/register', { email, password, code, name: '虚构客户端测试律师' })).status, 201);
  return email;
}

/** 异步运行真实 Dart 网络层，保持 Nest 事件循环可响应请求。 */
async function dart(origin, emails) {
  const result = await new Promise((resolveResult, reject) => {
    const child = spawn('dart', ['run', 'tool/connected_e2e.dart'], { cwd: resolve(root, 'client'),
      env: { ...process.env, RULER_E2E_URL: origin, RULER_E2E_ACCOUNTS: JSON.stringify(emails),
        RULER_E2E_PASSWORD: password }, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.resume(); // 不输出潜在包含请求凭据的原始异常。
    const timer = setTimeout(() => { child.kill(); reject(new Error('客户端联调超时')); }, 120_000);
    child.on('error', () => { clearTimeout(timer); reject(new Error('无法运行 Dart 联调')); });
    child.on('exit', code => { clearTimeout(timer); resolveResult({ code, stdout }); });
  });
  if (result.code !== 0) throw new Error('真实 Dart 客户端联调失败');
  const summary = JSON.parse(result.stdout);
  assert.equal(summary.passed, 6);
  assert.equal(summary.failed, 0);
  writeFileSync(resolve(output, 'client-api-validation.json'), JSON.stringify(summary, null, 2));
  console.log(`PASS 真实 Dart → Nest → PostgreSQL/Redis 联调：${summary.passed} 项`);
}

let app;
let created = false;
try {
  ddl('CREATE SCHEMA :"owned_schema";\n');
  created = true;
  run(process.execPath, [resolve(backend, 'node_modules/prisma/build/index.js'), 'migrate', 'deploy']);
  const { createApp } = await import(pathToFileURL(resolve(backend, 'dist/create-app.js')));
  const { DevelopmentMailbox } = await import(pathToFileURL(resolve(backend, 'dist/modules/auth/development-mailbox.js')));
  app = await createApp();
  await app.listen(0, '127.0.0.1');
  const origin = await app.getUrl();
  const emails = [await account(app, origin, DevelopmentMailbox), await account(app, origin, DevelopmentMailbox)];
  await dart(origin, emails);
} catch {
  console.error('FAIL 客户端真实联调未通过；未输出凭据或原始网络异常。');
  process.exitCode = 1;
} finally {
  if (app) await app.close();
  const redis = new Redis(process.env.REDIS_URL);
  try {
    let cursor = '0';
    do {
      const page = await redis.scan(cursor, 'MATCH', `${prefix}*`, 'COUNT', 100);
      cursor = page[0];
      if (page[1].length) await redis.del(...page[1]);
    } while (cursor !== '0');
  } finally { await redis.quit(); }
  if (created) ddl('SET client_min_messages TO WARNING; DROP SCHEMA :"owned_schema" CASCADE;\n');
}
