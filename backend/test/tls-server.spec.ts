import { INestApplication } from '@nestjs/common';
import { createApp } from '../src/create-app';
import { tlsFixture, tlsGet } from './tls-fixture';

describe('真实 Nest HTTPS 入口与证书拒绝', (): void => {
  let fixture: ReturnType<typeof tlsFixture>;
  let app: INestApplication;
  let origin: string;
  let saved: Record<string, string | undefined>;
  beforeAll(async (): Promise<void> => {
    fixture = tlsFixture();
    saved = Object.fromEntries(Object.keys(fixture.environment).map((key): [string, string | undefined] => [key, process.env[key]]));
    Object.assign(process.env, fixture.environment);
    app = await createApp();
    await app.listen(0, '127.0.0.1');
    origin = await app.getUrl();
  });
  afterAll(async (): Promise<void> => {
    try { if (app) await app.close(); }
    finally {
      fixture?.close();
      for (const [key, value] of Object.entries(saved ?? {})) {
        if (value === undefined) delete process.env[key]; else process.env[key] = value;
      }
    }
  });
  it('实际应用提供 HTTPS，显式信任本次证书后健康检查成功', async (): Promise<void> => {
    expect(origin.startsWith('https://')).toBe(true);
    expect(await tlsGet(origin, fixture.cert)).toBe(200);
  });
  it('未信任证书的客户端被拒绝', async (): Promise<void> => {
    await expect(tlsGet(origin)).rejects.toThrow('TLS_REJECTED');
  });
  it('即使信任证书，主机名称不匹配也拒绝', async (): Promise<void> => {
    await expect(tlsGet(origin, fixture.cert, 'wrong.example.invalid')).rejects.toThrow('HOSTNAME_REJECTED');
  });
  it('应用工厂遇到半套配置立即失败，不静默退回 HTTP', async (): Promise<void> => {
    const value = process.env.RULER_TLS_KEY_FILE;
    delete process.env.RULER_TLS_KEY_FILE;
    try { await expect(createApp()).rejects.toThrow(/^本机 HTTPS 配置无效$/); }
    finally { process.env.RULER_TLS_KEY_FILE = value; }
  });
});
