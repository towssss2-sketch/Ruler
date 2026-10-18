import { INestApplication } from '@nestjs/common';
import { request } from 'node:https';
import { readFileSync } from 'node:fs';
import { createApp } from '../src/create-app';
import { AuthRedisService } from '../src/modules/auth/auth-redis.service';
import { AuthService } from '../src/modules/auth/auth.service';
import { tlsFixture } from './tls-fixture';

export let app: INestApplication;
export let tls: ReturnType<typeof tlsFixture>;
let origin: string;
let saved: NodeJS.ProcessEnv;
export let redis: AuthRedisService;
export let auth: AuthService;

/** 安装隔离入口测试的独立应用、环境恢复及限流调用监视。 */
export function installRestrictedFixture(): void {
  beforeAll(async (): Promise<void> => {
    tls = tlsFixture();
    const environment = { ...tls.environment, RULER_RUNTIME_PROFILE: 'restricted-local' };
    saved = Object.fromEntries(Object.keys(environment).map((key): [string, string | undefined] => [key, process.env[key]]));
    Object.assign(process.env, environment);
    app = await createApp();
    await app.listen(0, '127.0.0.1');
    origin = await app.getUrl();
    redis = app.get(AuthRedisService); auth = app.get(AuthService);
  });
  beforeEach((): void => {
    jest.spyOn(redis, 'requestCode'); jest.spyOn(redis, 'limit').mockResolvedValue(undefined); jest.spyOn(auth, 'register');
  });
  afterEach((): void => { jest.restoreAllMocks(); });
  afterAll(async (): Promise<void> => {
    try { if (app) await app.close(); }
    finally {
      tls?.close();
      for (const [key, value] of Object.entries(saved ?? {})) {
        if (value === undefined) delete process.env[key]; else process.env[key] = value;
      }
    }
  });
}

/** 使用真实 TLS 请求，只返回状态；不输出正文、令牌、路径或证书材料。 */
export async function status(path: string, method = 'POST'): Promise<number> {
  return new Promise((resolve, reject): void => {
    const req = request(`${origin}${path}`, { method, ca: readFileSync(tls.cert), agent: false,
      headers: { 'content-type': 'application/json', 'x-ruler-runtime-profile': 'development',
        authorization: 'Bearer fictional-token', 'x-forwarded-for': '127.0.0.1', 'x-http-method-override': 'POST' } }, response => {
      response.resume(); response.on('end', (): void => { resolve(response.statusCode ?? 0); });
      response.on('error', (): void => { reject(new Error('测试响应失败')); });
    });
    req.setTimeout(5000, (): void => { req.destroy(); });
    req.on('error', (): void => { reject(new Error('测试请求失败')); });
    req.end(method === 'POST' ? JSON.stringify({ email: 'fictional@example.invalid', RULER_RUNTIME_PROFILE: 'development' }) : undefined);
  });
}
