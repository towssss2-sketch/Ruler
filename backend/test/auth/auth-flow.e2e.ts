import { createHash, randomUUID } from 'node:crypto';
import { JwtService } from '@nestjs/jwt';
import { installFixture, register, login, request, repository, password } from './fixture';
import { TokenPair } from '../../src/modules/auth/session.service';

installFixture();

describe('真实注册登录与用户数据边界', (): void => {
  it('注册、登录、携带 token 访问当前用户，密码与刷新原文均不落库', async (): Promise<void> => {
    const account = await register();
    const tokens = await login(account);
    const me = await request('/auth/me', undefined, tokens.accessToken);
    expect(me.status).toBe(200);
    expect(me.data.id).toBe(account.id);
    expect(Object.keys(me.data).sort()).toEqual(['email', 'id', 'name', 'tier']);
    expect((await request('/users/me', undefined, tokens.accessToken)).status).toBe(200);
    const user = await repository.db.user.findUniqueOrThrow({ where: { id: account.id } });
    expect(user.passwordHash.includes(password)).toBe(false);
    const row = await repository.db.refreshCredential.findUnique({ where: {
      tokenHash: createHash('sha256').update(tokens.refreshToken).digest('hex'),
    } });
    expect(Boolean(row)).toBe(true);
    expect(tokens.expiresIn).toBe(7200);
    const claims = new JwtService().decode<Record<string, unknown>>(tokens.accessToken);
    expect(Number(claims.exp) - Number(claims.iat)).toBe(7200);
    expect(Math.abs(Date.parse(tokens.refreshExpiresAt) - Date.now() - 30 * 86_400_000) < 5000).toBe(true);
  });
  it('错误密码与未知邮箱均返回相同 401，额外字段不能注册管理员', async (): Promise<void> => {
    const account = await register();
    const incorrect = await request('/auth/login', { email: account.email, password: 'Wrong-Fictional-Password!' });
    const absent = await request('/auth/login', { email: `${randomUUID()}@example.invalid`, password });
    expect([incorrect.status, absent.status]).toEqual([401, 401]);
    expect((await request('/auth/register', { email: account.email, password, name: '虚构', code: '000000', tier: 'PREMIUM' })).status).toBe(400);
  });
});

describe('轮换、重放与即时登出', (): void => {
  it('轮换保持原三十天期限；旧 token 重放后新 Access/Refresh 一并失效', async (): Promise<void> => {
    const first = await login(await register());
    const refreshed = await request('/auth/refresh', { refreshToken: first.refreshToken });
    expect(refreshed.status).toBe(200);
    const next = refreshed.data as unknown as TokenPair;
    expect(next.refreshToken === first.refreshToken).toBe(false);
    expect(next.refreshExpiresAt === first.refreshExpiresAt).toBe(true);
    expect((await request('/auth/me', undefined, next.accessToken)).status).toBe(200);
    expect((await request('/auth/refresh', { refreshToken: first.refreshToken })).status).toBe(401);
    expect((await request('/auth/me', undefined, next.accessToken)).status).toBe(401);
    expect((await request('/auth/refresh', { refreshToken: next.refreshToken })).status).toBe(401);
    expect(await repository.db.auditLog.count({ where: { action: 'AUTH_REFRESH_REPLAY' } })).toBeGreaterThan(0);
  });
  it('登出立即拒绝当前会话，另一设备的独立会话继续有效', async (): Promise<void> => {
    const account = await register();
    const first = await login(account);
    const second = await login(account);
    expect((await request('/auth/logout', {}, first.accessToken)).status).toBe(200);
    expect((await request('/auth/me', undefined, first.accessToken)).status).toBe(401);
    expect((await request('/auth/refresh', { refreshToken: first.refreshToken })).status).toBe(401);
    expect((await request('/auth/me', undefined, second.accessToken)).status).toBe(200);
  });
  it('同一刷新凭据并发提交只有一次轮换，重放检测最终吊销会话', async (): Promise<void> => {
    const tokens = await login(await register());
    const results = await Promise.all([request('/auth/refresh', { refreshToken: tokens.refreshToken }),
      request('/auth/refresh', { refreshToken: tokens.refreshToken })]);
    expect(results.map((result): number => result.status).sort()).toEqual([200, 401]);
    const winner = results.find((result): boolean => result.status === 200)!;
    expect((await request('/auth/me', undefined, winner.data.accessToken as string)).status).toBe(401);
  });
});
