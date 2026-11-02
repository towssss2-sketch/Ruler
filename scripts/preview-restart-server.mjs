import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

// 只由隔离集成测试派生；不为应用添加故障开关或公开测试接口。
const require = createRequire(new URL('../backend/package.json', import.meta.url));
assert.equal(process.env.NODE_ENV, 'test');
assert.equal(typeof process.send, 'function');
const database = new URL(process.env.DATABASE_URL);
const schema = database.searchParams.get('schema');
assert.match(schema ?? '', /^ruler_auth_[a-f0-9]{32}$/);
assert.equal(process.env.AUTH_REDIS_PREFIX, `ruler:auth:test:${schema.slice(11)}:`);
for (const endpoint of [database, new URL(process.env.REDIS_URL), new URL(process.env.MINIO_ENDPOINT)]) {
  assert.ok(['127.0.0.1', 'localhost'].includes(endpoint.hostname));
}
assert.match(process.env.STORAGE_BUCKET ?? '', /^ruler-document-test-[a-f0-9-]{36}$/);
assert.equal(process.env.STORAGE_DRIVER, 'minio');
const { createApp } = require('./dist/create-app.js');
const { StorageService } = require('./dist/modules/document/storage/storage.service.js');
const app = await createApp();
if (process.argv.includes('--pause-read')) {
  app.get(StorageService).read = () => {
    process.send({ type: 'READ_PENDING' });
    return new Promise(() => {});
  };
}
await app.listen(0, '127.0.0.1');
process.send({ type: 'READY', origin: await app.getUrl() });
let closing = false;
async function close() {
  if (closing) return;
  closing = true;
  const force = setTimeout(() => process.exit(1), 3000);
  force.unref();
  try { await app.close(); process.exit(0); }
  catch { process.exit(1); }
}
process.on('SIGTERM', close);
process.on('disconnect', close);
setTimeout(close, 180000).unref();
