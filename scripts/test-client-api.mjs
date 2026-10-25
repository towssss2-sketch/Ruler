import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { randomBytes, randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';
import { clientStorageFixture } from './client-storage-fixture.mjs';
import { testTlsFixture, tlsStorageFixture } from './test-tls-fixture.mjs';
import { request as httpsRequest } from 'node:https';
import { checkRestrictedEntries } from './restricted-local-check.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const backend = resolve(root, 'backend');
const require = createRequire(resolve(backend, 'package.json'));
const Redis = require('ioredis');
const restricted = process.argv.includes('--restricted');
const useTls = restricted || process.argv.includes('--https');
const resultName = restricted ? 'client-restricted-validation.json' : useTls ? 'client-https-validation.json' : 'client-api-validation.json';
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
  const post = (path, data) => tls ? tlsPost(`${origin}${path}`, data, tls.cert) : fetch(`${origin}${path}`, { method: 'POST',
    headers: { 'content-type': 'application/json' }, body: JSON.stringify(data) });
  assert.equal((await post('/auth/verification-code', { email })).status, 200);
  const code = app.get(Mailbox).take(email);
  assert.equal(typeof code, 'string');
  assert.equal((await post('/auth/register', { email, password, code, name: '虚构客户端测试律师' })).status, 201);
  return email;
}

/** 注册准备也严格验证本次证书，不使用全局关闭校验或任何公开取码接口。 */
async function tlsPost(url, data, ca, method = 'POST') {
  return new Promise((resolveReply, reject) => {
    const body = data === undefined ? undefined : JSON.stringify(data);
    const req = httpsRequest(url, { method, ca, agent: false,
      headers: body ? { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) } : {} }, response => {
      response.resume();
      response.on('end', () => resolveReply({ status: response.statusCode }));
      response.on('error', () => reject(new Error('HTTPS 测试账号准备失败')));
    });
    req.setTimeout(10000, () => req.destroy());
    req.on('error', () => reject(new Error('HTTPS 测试账号准备失败')));
    req.end(body);
  });
}

/** 异步运行真实 Dart 网络层，保持 Nest 事件循环可响应请求。 */
async function dart(origin, emails, storageOrigin) {
  const result = await new Promise((resolveResult, reject) => {
    const child = spawn('dart', ['run', 'tool/connected_e2e.dart'], { cwd: resolve(root, 'client'),
      env: { ...process.env, RULER_E2E_URL: origin, RULER_E2E_ACCOUNTS: JSON.stringify(emails),
        RULER_E2E_PASSWORD: password, RULER_E2E_STORAGE: storageOrigin,
        ...(tls ? { RULER_E2E_CA_FILE: tls.certFile } : {}) }, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.resume(); // 不输出潜在包含请求凭据的原始异常。
    const timer = setTimeout(() => { child.kill(); reject(new Error('客户端联调超时')); }, 120_000);
    child.on('error', () => { clearTimeout(timer); reject(new Error('无法运行 Dart 联调')); });
    child.on('exit', code => { clearTimeout(timer); resolveResult({ code, stdout }); });
  });
  if (result.code !== 0) throw new Error('真实 Dart 客户端联调失败');
  const summary = JSON.parse(result.stdout);
  assert.equal(summary.passed, useTls ? 20 : 19);
  assert.equal(summary.failed, 0);
  assert.equal(summary.skipped, 0);
  assert.equal(summary.tls, useTls ? 'LOCAL_TRUSTED_CERTIFICATE' : 'HTTP_LOOPBACK');
  summary.runtimeProfile = restricted ? 'restricted-local' : 'development';
  if (restricted) {
    assert.deepEqual(await restrictedEntries(origin), boundaryChecks);
    summary.boundaryChecks = boundaryChecks;
    summary.serviceRestarted = true;
  }
  if (gateway) {
    assert.ok(gateway.state.put > 0 && gateway.state.get > 0);
    assert.equal(gateway.state.credentialHeaderObserved, false);
    summary.storageIngress = { separateHttps: true, jwtOrCookieObserved: false };
  }
  writeFileSync(resolve(output, resultName), JSON.stringify(summary, null, 2));
  console.log(`PASS 真实 Dart ${restricted ? '隔离模式双 HTTPS' : useTls ? '双 HTTPS' : 'HTTP'} → Nest → PostgreSQL/Redis/MinIO 联调：${summary.passed} 项`);
  if (restricted) console.log(`PASS 隔离入口检查：${boundaryChecks.length} 项，业务联调前后均拒绝`);
}

/** 使用本次可信证书检查真实入口，保留 TLS 主机校验。 */
function restrictedEntries(origin) {
  return checkRestrictedEntries((path, method) => tlsPost(`${origin}${path}`,
    method === 'POST' ? { email: 'fictional@example.invalid' } : undefined, tls.cert, method));
}

/** 每项资源独立清理；某项失败不跳过其他资源，也不回显凭据。 */
async function cleanup(action) {
  try { await action(); }
  catch {
    console.error('FAIL 本次隔离测试资源未完整清理，请检查开发环境。');
    process.exitCode = 1;
  }
}

let app;
let storage;
let tls;
let gateway;
let boundaryChecks;
let created = false;
try {
  ddl('CREATE SCHEMA :"owned_schema";\n');
  created = true;
  run(process.execPath, [resolve(backend, 'node_modules/prisma/build/index.js'), 'migrate', 'deploy']);
  storage = await clientStorageFixture(id);
  // 本次子进程选择明确模式，绝不继承另一轮的证书或签名入口设置。
  delete process.env.RULER_E2E_CA_FILE;
  delete process.env.RULER_TLS_CERT_FILE;
  delete process.env.RULER_TLS_KEY_FILE;
  delete process.env.MINIO_SIGNING_ENDPOINT;
  delete process.env.RULER_RUNTIME_PROFILE;
  if (useTls) {
    tls = testTlsFixture();
    gateway = await tlsStorageFixture(storage.origin, tls);
    Object.assign(process.env, { HOST: '127.0.0.1', RULER_TLS_CERT_FILE: tls.certFile,
      RULER_TLS_KEY_FILE: tls.keyFile, MINIO_SIGNING_ENDPOINT: gateway.origin });
  }
  const { createApp } = await import(pathToFileURL(resolve(backend, 'dist/create-app.js')));
  const { DevelopmentMailbox } = await import(pathToFileURL(resolve(backend, 'dist/modules/auth/development-mailbox.js')));
  app = await createApp();
  await app.listen(0, '127.0.0.1');
  let origin = await app.getUrl();
  const emails = [await account(app, origin, DevelopmentMailbox), await account(app, origin, DevelopmentMailbox)];
  if (restricted) {
    await app.close();
    app = undefined;
    process.env.RULER_RUNTIME_PROFILE = 'restricted-local';
    app = await createApp();
    await app.listen(0, '127.0.0.1');
    origin = await app.getUrl();
    boundaryChecks = await restrictedEntries(origin);
  }
  await dart(origin, emails, gateway?.origin ?? storage.origin);
} catch {
  console.error('FAIL 客户端真实联调未通过；未输出凭据或原始网络异常。');
  process.exitCode = 1;
} finally {
  if (app) await cleanup(() => app.close());
  if (gateway) await cleanup(() => gateway.close());
  if (tls) await cleanup(() => tls.close());
  if (storage) await cleanup(() => storage.close());
  await cleanup(async () => {
    const redis = new Redis(process.env.REDIS_URL);
    try {
    let cursor = '0';
    do {
      const page = await redis.scan(cursor, 'MATCH', `${prefix}*`, 'COUNT', 100);
      cursor = page[0];
      if (page[1].length) await redis.del(...page[1]);
    } while (cursor !== '0');
    } finally { await redis.quit(); }
  });
  if (created) await cleanup(() => ddl('SET client_min_messages TO WARNING; DROP SCHEMA :"owned_schema" CASCADE;\n'));
}
