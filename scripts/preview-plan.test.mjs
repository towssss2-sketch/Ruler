import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { evaluatePlan, isPublicHttpsOrigin } from './preview-plan.mjs';
import { probeCurrentStorage } from './preview-probe.mjs';
const fixture = () => JSON.parse(readFileSync(new URL('../infra/preview/plan.json', import.meta.url), 'utf8'));

test('没有资源的提案格式有效，但部署、连通性、账号及真机都不计通过', () => {
  const result = evaluatePlan(fixture());
  assert.equal(result.configurationValid, true);
  assert.equal(result.status, 'BLOCKED');
  assert.equal(result.approval, 'PENDING_D10');
  assert.equal(result.deployment, 'NOT_DEPLOYED');
  assert.equal(result.connectivity, 'NOT_RUN');
  assert.equal(result.accountDelivery, 'NOT_RUN');
  assert.equal(result.deviceAcceptance, 'NOT_RUN');
  assert.equal(result.endpointFormat, 'MISSING');
});
test('候选 HTTPS 地址仅验证格式，不能变成部署授权或公网可用证明', () => {
  const plan = fixture();
  plan.endpoints = { apiOrigin: 'https://api.ruler-fixture.org', storageOrigin: 'https://files.ruler-fixture.org:8443' };
  const result = evaluatePlan(plan);
  assert.equal(result.endpointFormat, 'VALID_FORMAT_ONLY');
  assert.equal(result.status, 'BLOCKED');
  assert.equal(result.approval, 'PENDING_D10');
  assert.equal(result.connectivity, 'NOT_RUN');
});
for (const [name, value] of [
  ['明文 HTTP', 'http://api.ruler-fixture.org'], ['本机域名', 'https://localhost'],
  ['IPv4', 'https://127.0.0.1'], ['非规范整数 IP', 'https://2130706433'],
  ['IPv6', 'https://[::1]'], ['内网域名', 'https://api.internal'],
  ['保留示例域名', 'https://api.example.com'], ['虚构域名', 'https://api.example.invalid'],
  ['带路径', 'https://api.ruler-fixture.org/path'], ['签名查询', 'https://api.ruler-fixture.org?signature=fictional'],
  ['用户凭据', 'https://user:fictional@api.ruler-fixture.org'], ['片段', 'https://api.ruler-fixture.org#fragment'],
  ['前导空格', ' https://api.ruler-fixture.org'], ['反斜线', 'https://api.ruler-fixture.org\\path'],
]) test(`拒绝${name}，报告不回显 URL`, () => {
  assert.equal(isPublicHttpsOrigin(value), false);
  const plan = fixture();
  plan.endpoints.apiOrigin = value;
  const result = evaluatePlan(plan);
  assert.equal(result.status, 'INVALID');
  assert.equal(JSON.stringify(result).includes(value), false);
});
for (const [name, mutate] of [
  ['开启真实数据', plan => { plan.policy.realDataAllowed = true; }],
  ['开放注册', plan => { plan.policy.publicRegistration = true; }],
  ['开放数据库端口', plan => { plan.policy.publicDataPorts = true; }],
  ['公开管理后台', plan => { plan.policy.publicConsole = true; }],
  ['自动续费', plan => { plan.budget.autoRenew = true; }],
  ['超出建议月预算', plan => { plan.budget.monthlyCapCny = 301; }],
  ['超出域名首年预算', plan => { plan.budget.domainFirstYearCapCny = 101; }],
  ['伪造授权', plan => { plan.approved = true; }],
  ['未知嵌套凭据', plan => { plan.resources.secret = 'fictional-secret-must-not-echo'; }],
  ['将 API 和文件源混为同一地址', plan => { plan.endpoints = { apiOrigin: 'https://api.ruler-fixture.org', storageOrigin: 'https://api.ruler-fixture.org' }; }],
]) test(`拒绝${name}，不泄露未知字段`, () => {
  const plan = fixture();
  mutate(plan);
  const result = evaluatePlan(plan);
  assert.equal(result.configurationValid, false);
  assert.equal(result.status, 'INVALID');
  assert.equal(JSON.stringify(result).includes('fictional-secret-must-not-echo'), false);
});
test('实际后端拒绝公网 MinIO 配置，离线签名指向本机；返回值不含签名或密钥', async () => {
  const result = await probeCurrentStorage();
  assert.deepEqual(result, { mode: 'OFFLINE_REAL_CODE', publicEndpointRejected: true,
    publicSigningEndpointRejected: true, independentLoopbackSigning: true, signedOriginIsLoopback: true });
  assert.doesNotMatch(JSON.stringify(result), /signature|credential|fictional-offline|https?:/i);
});
