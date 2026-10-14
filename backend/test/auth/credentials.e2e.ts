import { randomBytes, randomUUID } from 'node:crypto';
import { JwtService } from '@nestjs/jwt';
import { installFixture, register, login, request, repository, baseUrl } from './fixture';

installFixture();

describe('JWT 安全边界与实时账号状态', (): void => {
  it('错误算法、签名、受众、签发者、类型、过期和未来签发时间均 401', async (): Promise<void> => {
    const tokens = await login(await register());
    const codec = new JwtService();
    const original = codec.decode<Record<string, unknown>>(tokens.accessToken);
    const base = { sub: original.sub, sid: original.sid, jti: original.jti, type: 'access' };
    const signing = { secret: Buffer.from(process.env.AUTH_SIGNING_KEY!, 'hex'),
      issuer: 'ruler-development', audience: 'ruler-client', expiresIn: 7200 };
    const variants = [
      codec.sign(base, { ...signing, algorithm: 'HS384' }),
      codec.sign(base, { ...signing, secret: randomBytes(32) }),
      codec.sign(base, { ...signing, audience: 'wrong-client' }),
      codec.sign(base, { ...signing, issuer: 'wrong-issuer' }),
      codec.sign({ ...base, type: 'refresh' }, signing),
      codec.sign(base, { ...signing, expiresIn: -1 }),
      codec.sign({ ...base, iat: Math.floor(Date.now() / 1000) + 500 }, signing),
      codec.sign(base, { ...signing, expiresIn: 9000 }),
    ];
    for (const token of variants) expect((await request('/auth/me', undefined, token)).status).toBe(401);
    expect((await request('/auth/me', undefined, tokens.refreshToken)).status).toBe(401);
  });
  it('不接受 query/body token、错误 Bearer 格式或未签名 token', async (): Promise<void> => {
    const tokens = await login(await register());
    expect((await request(`/auth/me?accessToken=${tokens.accessToken}`)).status).toBe(401);
    const wrong = await fetch(`${baseUrl}/auth/me`, { headers: { authorization: `Basic ${tokens.accessToken}` } });
    expect(wrong.status).toBe(401);
    const unsigned = new JwtService().sign({ sub: randomUUID() }, { algorithm: 'none' });
    expect((await request('/auth/me', undefined, unsigned)).status).toBe(401);
    expect((await request('/auth/refresh', { refreshToken: randomBytes(32).toString('base64url') })).status).toBe(401);
  });
  it('软删除用户后 Access 与 Refresh 都被立即拒绝', async (): Promise<void> => {
    const account = await register();
    const tokens = await login(account);
    await repository.db.user.update({ where: { id: account.id }, data: { deletedAt: new Date() } });
    expect((await request('/auth/me', undefined, tokens.accessToken)).status).toBe(401);
    expect((await request('/auth/refresh', { refreshToken: tokens.refreshToken })).status).toBe(401);
    expect((await request('/auth/login', { email: account.email, password: 'Fictional-Test-Password-Only!' })).status).toBe(401);
  });
  it('会话超过绝对期限后不能刷新或使用 Access', async (): Promise<void> => {
    const account = await register();
    const tokens = await login(account);
    const session = await repository.db.authSession.findFirstOrThrow({ where: { userId: account.id } });
    await repository.db.authSession.update({ where: { id: session.id }, data: { expiresAt: new Date(session.createdAt.getTime() + 1) } });
    expect((await request('/auth/me', undefined, tokens.accessToken)).status).toBe(401);
    expect((await request('/auth/refresh', { refreshToken: tokens.refreshToken })).status).toBe(401);
  });
});
