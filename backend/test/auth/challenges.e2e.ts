import { randomUUID } from 'node:crypto';
import { installFixture, register, request, app, redis, prefix, password, baseUrl } from './fixture';
import { DevelopmentMailbox } from '../../src/modules/auth/development-mailbox';
import { AuthRedisService } from '../../src/modules/auth/auth-redis.service';

installFixture();

describe('验证码有效期、次数与一次性消费', (): void => {
  it('未验证、错误码与过期码均不能注册；Redis 不存明文验证码', async (): Promise<void> => {
    const email = `${randomUUID()}@example.invalid`;
    const input = { email, password, name: '虚构律师', code: '000000' };
    expect((await request('/auth/register', input)).status).toBe(401);
    expect((await request('/auth/verification-code', { email })).status).toBe(200);
    const code = app.get(DevelopmentMailbox).take(email)!;
    const service = app.get(AuthRedisService);
    const key = `${prefix}code:${service.digest(email, 'email')}`;
    const saved = await redis.hgetall(key);
    expect(Object.values(saved).includes(code)).toBe(false);
    expect(await redis.ttl(key)).toBeGreaterThan(0);
    const wrong = code === '111111' ? '222222' : '111111';
    expect((await request('/auth/register', { ...input, code: wrong })).status).toBe(401);
    await redis.expire(key, 0);
    expect((await request('/auth/register', { ...input, code })).status).toBe(401);
  });
  it('错误尝试五次即销毁，不能之后用正确码绕过', async (): Promise<void> => {
    const email = `${randomUUID()}@example.invalid`;
    await app.get(AuthRedisService).requestCode(email);
    const code = app.get(DevelopmentMailbox).take(email)!;
    const wrong = code === '111111' ? '222222' : '111111';
    for (let i = 0; i < 5; i++) expect(await app.get(AuthRedisService).consumeCode(email, wrong)).toBe(false);
    expect(await app.get(AuthRedisService).consumeCode(email, code)).toBe(false);
  });
  it('使用过的码不能重放；已验证但重复注册返回 409', async (): Promise<void> => {
    const email = `${randomUUID()}@example.invalid`;
    await request('/auth/verification-code', { email });
    const code = app.get(DevelopmentMailbox).take(email)!;
    const body = { email, password, name: '虚构律师', code };
    expect((await request('/auth/register', body)).status).toBe(201);
    expect((await request('/auth/register', body)).status).toBe(401);
    await request('/auth/verification-code', { email });
    const next = app.get(DevelopmentMailbox).take(email)!;
    expect((await request('/auth/register', { ...body, code: next })).status).toBe(409);
  });
});

describe('严格限流与虚构投递边界', (): void => {
  it('验证码按规范化邮箱限流，登录错误五次后 429', async (): Promise<void> => {
    const account = await register();
    for (let i = 0; i < 2; i++) expect((await request('/auth/verification-code', { email: account.email.toUpperCase() })).status).toBe(200);
    expect((await request('/auth/verification-code', { email: account.email })).status).toBe(429);
    for (let i = 0; i < 5; i++) expect((await request('/auth/login', { email: account.email, password: 'Wrong-Fictional-Password!' })).status).toBe(401);
    expect((await request('/auth/login', { email: account.email, password })).status).toBe(429);
  });
  it('更换邮箱和伪造转发 IP 不能绕过来源限流，健康接口不受影响', async (): Promise<void> => {
    for (let i = 0; i < 30; i++) {
      const response = await fetch(`${baseUrl}/auth/verification-code`, { method: 'POST', headers: {
        'content-type': 'application/json', 'x-forwarded-for': `192.0.2.${i + 1}` },
      body: JSON.stringify({ email: `${randomUUID()}@example.invalid` }) });
      expect(response.status).toBe(200);
    }
    expect((await request('/auth/verification-code', { email: `${randomUUID()}@example.invalid` })).status).toBe(429);
    expect((await request('/health')).status).toBe(200);
  });
  it('不向真实域发码，无公开取码端点，Swagger 不包含凭据', async (): Promise<void> => {
    expect((await request('/auth/verification-code', { email: 'fictional@example.com' })).status).toBe(400);
    expect((await request('/auth/verification-code/latest')).status).toBe(404);
    const response = await fetch(`${baseUrl}/docs-json`);
    expect(response.status).toBe(200);
    const text = await response.text();
    expect(text.includes(process.env.AUTH_SIGNING_KEY!)).toBe(false);
    expect(text.includes(process.env.AUTH_CHALLENGE_KEY!)).toBe(false);
    expect(text.includes('/auth/login')).toBe(true);
  });
  it('普通受保护 API 在身份校验前限流，避免伪造令牌无限撞库', async (): Promise<void> => {
    for (let i = 0; i < 120; i++) expect((await request('/auth/me')).status).toBe(401);
    expect((await request('/auth/me')).status).toBe(429);
    expect((await request('/health')).status).toBe(200);
  });
});
