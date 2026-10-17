import { createRequire } from 'node:module';
import { isIP } from 'node:net';
const require = createRequire(new URL('../backend/package.json', import.meta.url));
const { z } = require('zod');

/** 只检查候选地址格式，不查 DNS、不连接服务；返回布尔值，不回显输入。 */
export function isPublicHttpsOrigin(value) {
  if (typeof value !== 'string' || value.length > 253) return false;
  try {
    const url = new URL(value);
    const host = url.hostname;
    return url.protocol === 'https:' && !url.username && !url.password && !url.search && !url.hash
      && value === url.origin && !isIP(host) && host.includes('.')
      && /^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/.test(host)
      && !/(^|\.)(localhost|local|internal|invalid|test|example|home|lan)$/.test(host)
      && !/(^|\.)example\.(com|net|org)$/.test(host);
  } catch { return false; }
}

const origin = z.string().refine(value => value === '' || isPublicHttpsOrigin(value));
const schema = z.object({
  schemaVersion: z.literal(1),
  purpose: z.literal('FICTIONAL_TEST_ONLY'),
  resources: z.object({ provider: z.literal('aliyun'), proposedRegion: z.literal('cn-hongkong'),
    cpu: z.literal(2), memoryGiB: z.literal(4), diskGiB: z.literal(60) }).strict(),
  budget: z.object({ monthlyCapCny: z.literal(300),
    domainFirstYearCapCny: z.literal(100), autoRenew: z.literal(false) }).strict(),
  endpoints: z.object({ apiOrigin: origin, storageOrigin: origin }).strict(),
  policy: z.object({ realDataAllowed: z.literal(false), publicRegistration: z.literal(false),
    publicDataPorts: z.literal(false), publicConsole: z.literal(false) }).strict(),
  lifecycle: z.object({ testAccounts: z.literal(2), trialDays: z.literal(7), retentionDays: z.literal(7) }).strict(),
}).strict().refine(plan => !plan.endpoints.apiOrigin || !plan.endpoints.storageOrigin
  || plan.endpoints.apiOrigin !== plan.endpoints.storageOrigin);

/** 校验本轮具体提案；未知字段或危险选项均拒绝，不接收凭据、授权标志或真实状态声明。 */
export function evaluatePlan(input) {
  const parsed = schema.safeParse(input);
  if (!parsed.success) return { configurationValid: false, status: 'INVALID', issues: ['方案格式或边界无效；不回显输入'] };
  return { configurationValid: true, status: 'BLOCKED', approval: 'PENDING_D10', deployment: 'NOT_DEPLOYED',
    connectivity: 'NOT_RUN', accountDelivery: 'NOT_RUN', deviceAcceptance: 'NOT_RUN',
    endpointFormat: parsed.data.endpoints.apiOrigin && parsed.data.endpoints.storageOrigin ? 'VALID_FORMAT_ONLY' : 'MISSING',
    issues: ['用户尚无服务器和域名；没有购买、部署授权', '报价、地域及公网测试边界尚待确认',
      'HTTPS、可达存储签名、受控账号交付和测试入口隔离尚待实现',
      'D-06 依赖维护问题尚未处理，公网开放前须评估并验证',
      '手机及 Windows 远程登录、上传、下载尚未验收'] };
}
