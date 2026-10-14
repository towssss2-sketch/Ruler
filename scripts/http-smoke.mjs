import assert from 'node:assert/strict';
import { setTimeout } from 'node:timers/promises';

const baseUrl = `http://${process.env.HOST}:${process.env.PORT}`;
let response;
for (let attempt = 0; attempt < 30; attempt += 1) {
  try {
    response = await fetch(`${baseUrl}/health/ready`, { signal: AbortSignal.timeout(2000) });
    if (response.ok) break;
  } catch { /* 启动窗口内重试；最终必须拿到正常数据库就绪响应。 */ }
  await setTimeout(500);
}
assert.equal(response?.status, 200, '后端/数据库未就绪');
const ready = await response.json();
assert.deepEqual(ready.data, { status: 'ok', stage: 0 });
assert.equal(ready.code, 0);
assert.match(ready.traceId, /^[0-9a-f-]{36}$/);
const unknown = await fetch(`${baseUrl}/cases?private=fictional-input`);
assert.equal(unknown.status, 404);
assert.equal((await unknown.text()).includes('fictional-input'), false);
console.log('PASS 已构建后端：真实数据库就绪 HTTP 200、标准响应、未实现业务 404 和输入不回显');
