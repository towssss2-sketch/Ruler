import { INestApplication } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import Redis from 'ioredis';
import { createApp } from '../../src/create-app';
import { PrismaRepository } from '../../src/prisma.repository';
import { DevelopmentMailbox } from '../../src/modules/auth/development-mailbox';
import { TokenPair } from '../../src/modules/auth/session.service';

export let app: INestApplication;
export let baseUrl: string;
export let repository: PrismaRepository;
export let redis: Redis;
export const prefix = process.env.AUTH_REDIS_PREFIX!;
export const password = 'Fictional-Test-Password-Only!';
export interface Reply { status: number; data: Record<string, unknown>; raw: string }
export interface Account { id: string; email: string }

/** 仅删除本次测试的随机前缀，不允许 FLUSHDB/FLUSHALL。 */
export async function clearRedis(): Promise<void> {
  if (!/^ruler:auth:test:[a-f0-9]{32}:$/.test(prefix)) throw new Error('拒绝清理非测试 Redis 前缀');
  let cursor = '0';
  do {
    const page = await redis.scan(cursor, 'MATCH', `${prefix}*`, 'COUNT', 100);
    cursor = page[0];
    if (page[1].length) await redis.del(...page[1]);
  } while (cursor !== '0');
}

/** 自动启动真实 HTTP/数据库/Redis 测试实例，端口随机、只绑定回环。 */
export function installFixture(): void {
  beforeAll(async (): Promise<void> => {
    app = await createApp();
    await app.listen(0, '127.0.0.1');
    baseUrl = await app.getUrl();
    repository = app.get(PrismaRepository);
    redis = new Redis(process.env.REDIS_URL!);
  });
  beforeEach(clearRedis);
  afterAll(async (): Promise<void> => {
    await clearRedis();
    await redis.quit();
    await app.close();
  });
}

/** 解析 HTTP 标准信封，断言只输出状态，不将令牌或验证码写入失败日志。 */
export async function request(path: string, body?: unknown, access?: string, method?: string): Promise<Reply> {
  const response = await fetch(`${baseUrl}${path}`, { method: method ?? (body === undefined ? 'GET' : 'POST'),
    headers: { ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      ...(access ? { authorization: `Bearer ${access}` } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) });
  const raw = await response.text();
  const envelope = JSON.parse(raw) as { data: Record<string, unknown> | null };
  return { status: response.status, data: envelope.data ?? {}, raw };
}

/** 完整验证码注册流程，验证码只在内存适配器中读取，不提供绕过接口。 */
export async function register(): Promise<Account> {
  const email = `fictional-${randomUUID()}@example.invalid`;
  const sent = await request('/auth/verification-code', { email });
  expect(sent.status).toBe(200);
  const code = app.get(DevelopmentMailbox).take(email);
  expect(typeof code).toBe('string');
  expect(sent.raw.includes(code!)).toBe(false);
  const response = await request('/auth/register', { email, password, code, name: '虚构测试律师' });
  expect(response.status).toBe(201);
  return { id: response.data.id as string, email };
}

/** 真实邮箱密码登录，只返回内存中的令牌，不打印凭据。 */
export async function login(account: Account): Promise<TokenPair> {
  const response = await request('/auth/login', { email: account.email, password });
  expect(response.status).toBe(200);
  return response.data as unknown as TokenPair;
}

/** 准备隔离库的虚构资源，不把测试准备说成已实现案件 CRUD。 */
export async function createCase(userId: string): Promise<string> {
  const record = await repository.db.case.create({ data: { ownerId: userId, caseNo: `虚构-${randomUUID()}`,
    cause: '虚构案由', court: '虚构法院', members: { create: { userId, invitedBy: userId,
      role: 'OWNER', status: 'ACCEPTED', acceptedAt: new Date() } } } });
  return record.id;
}
