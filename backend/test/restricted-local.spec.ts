import { createApp } from '../src/create-app';
import { auth, redis, tls, status, installRestrictedFixture } from './restricted-fixture';

describe('本机隔离模式真实 HTTPS 开发入口关闭', (): void => {
  installRestrictedFixture();

  it.each([
    '/auth/register', '/AUTH/REGISTER', '/auth/register/', '/auth/register?mode=development',
    '/auth/verification-code', '/AUTH/VERIFICATION-CODE', '/auth/verification-code/', '/auth/verification-code?mode=development',
    '/auth/%72egister', '/auth//register', '//auth/register', '/auth/register/extra',
  ])('注册及验证码绕过路径均拒绝 %s', async (path: string): Promise<void> => {
    expect(await status(path)).toBe(404);
    expect(redis.requestCode).not.toHaveBeenCalled(); expect(redis.limit).not.toHaveBeenCalled();
    expect(auth.register).not.toHaveBeenCalled();
  });
  it.each(['/docs', '/docs/', '/docs-json', '/docs-yaml', '/docs/swagger-ui-init.js', '/DOCS', '/docs-json?mode=development'])(
    '不注册文档页面、资源或规范 %s', async (path: string): Promise<void> => { expect(await status(path, 'GET')).toBe(404); });
  it.each(['GET', 'HEAD', 'PUT', 'PATCH', 'DELETE'])('其他方法不能打开注册入口 %s', async (method: string): Promise<void> => {
    expect(await status('/auth/register', method)).toBe(404);
  });
  it('启动后环境变量变更不能重新打开入口；重复请求不消耗验证码限流', async (): Promise<void> => {
    process.env.RULER_RUNTIME_PROFILE = 'development';
    try {
      for (let i = 0; i < 35; i++) expect(await status('/auth/verification-code')).toBe(404);
      expect(redis.limit).not.toHaveBeenCalled(); expect(redis.requestCode).not.toHaveBeenCalled();
    } finally { process.env.RULER_RUNTIME_PROFILE = 'restricted-local'; }
  });
  it('健康检查保留；登录及刷新仍处理输入；私有接口仍需有效身份', async (): Promise<void> => {
    expect(await status('/health', 'GET')).toBe(200);
    expect(await status('/auth/login')).toBe(400);
    expect(await status('/auth/refresh')).toBe(400);
    expect(await status('/auth/me', 'GET')).toBe(401);
  });
  it('实际工厂拒绝无 TLS 的隔离模式', async (): Promise<void> => {
    delete process.env.RULER_TLS_KEY_FILE;
    try { await expect(createApp()).rejects.toThrow(/^运行模式配置无效$/); }
    finally { process.env.RULER_TLS_KEY_FILE = tls.key; }
  });
});
