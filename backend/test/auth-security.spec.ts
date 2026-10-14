import { randomBytes, randomUUID } from 'node:crypto';
import { ExecutionContext } from '@nestjs/common';
import { loadAuthConfig } from '../src/modules/auth/auth-config';
import { AuthRedisService } from '../src/modules/auth/auth-redis.service';
import { DevelopmentMailbox } from '../src/modules/auth/development-mailbox';
import { CaseAccessService } from '../src/modules/case/case-access.service';
import { CaseAccessGuard } from '../src/modules/case/case-access.guard';
import { PrismaRepository } from '../src/prisma.repository';

const config = { NODE_ENV: 'test', AUTH_SIGNING_KEY: randomBytes(32).toString('hex'),
  AUTH_CHALLENGE_KEY: randomBytes(32).toString('hex'), REDIS_URL: 'redis://127.0.0.1:6379' };

describe('安全配置与失效关闭', (): void => {
  it('拒绝生产模式、缺失/重复密钥及远程或非法 Redis 配置，不输出值', (): void => {
    expect((): void => { loadAuthConfig({}); }).toThrow('鉴权配置无效');
    expect((): void => { loadAuthConfig({ ...config, NODE_ENV: 'production' }); }).toThrow();
    expect((): void => { loadAuthConfig({ ...config, AUTH_CHALLENGE_KEY: config.AUTH_SIGNING_KEY }); }).toThrow();
    for (const REDIS_URL of ['bad-url', 'redis://remote.example.invalid', 'https://127.0.0.1']) {
      expect((): void => { loadAuthConfig({ ...config, REDIS_URL }); }).toThrow('REDIS_URL');
    }
  });
  it('Redis 不可达即拒绝入口，不在内存继续计数或发码', async (): Promise<void> => {
    const service = new AuthRedisService(loadAuthConfig({ ...config, REDIS_URL: 'redis://127.0.0.1:19999' }), new DevelopmentMailbox());
    try { await expect(service.limit('login', 'fictional@example.invalid', 5)).rejects.toMatchObject({ status: 503 }); }
    finally { await service.onModuleDestroy(); }
  });
  it('验证码内存适配器取码一次，真实邮箱禁止投递，过期码不返回', async (): Promise<void> => {
    const mailbox = new DevelopmentMailbox();
    await expect(mailbox.send('fictional@example.com', '000000')).rejects.toThrow();
    await mailbox.send('fictional@example.invalid', '000000');
    expect(typeof mailbox.take('fictional@example.invalid')).toBe('string');
    expect(mailbox.take('fictional@example.invalid')).toBeUndefined();
    await mailbox.send('expired@example.invalid', '000000');
    const spy = jest.spyOn(Date, 'now').mockReturnValue(Date.now() + 700_000);
    try {
      expect(mailbox.take('expired@example.invalid')).toBeUndefined();
      await mailbox.send('fresh@example.invalid', '000000');
    } finally { spy.mockRestore(); }
  });
});

describe('资源守卫默认拒绝', (): void => {
  it('无路径资源和未注入身份都不能放行', async (): Promise<void> => {
    const repository = new PrismaRepository();
    const service = new CaseAccessService(repository);
    try {
      await expect(service.authorize(randomUUID(), {}, 'GET')).rejects.toMatchObject({ status: 403 });
      const context = { switchToHttp: (): object => ({ getRequest: (): object => ({ params: {} }) }) } as ExecutionContext;
      await expect(new CaseAccessGuard(service).canActivate(context)).rejects.toMatchObject({ status: 401 });
    } finally { await repository.onModuleDestroy(); }
  });
});
