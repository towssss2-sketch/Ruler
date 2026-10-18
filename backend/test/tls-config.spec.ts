import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { loadTlsOptions } from '../src/tls-config';
import { tlsFixture } from './tls-fixture';

describe('本机 HTTPS 启动配置', (): void => {
  let fixture: ReturnType<typeof tlsFixture>;
  beforeAll((): void => { fixture = tlsFixture(); });
  afterAll((): void => { fixture.close(); });
  afterEach((): void => { jest.restoreAllMocks(); });
  it('未启用时兼容原 HTTP；完整有效材料启用 TLS 1.2 以上', (): void => {
    expect(loadTlsOptions({})).toBeUndefined();
    const options = loadTlsOptions(fixture.environment);
    expect(options?.minVersion).toBe('TLSv1.2');
    expect(Buffer.isBuffer(options?.key)).toBe(true);
    expect(Buffer.isBuffer(options?.cert)).toBe(true);
  });
  it.each([
    { RULER_TLS_KEY_FILE: undefined }, { RULER_TLS_CERT_FILE: undefined },
    { RULER_TLS_KEY_FILE: '' }, { RULER_TLS_CERT_FILE: 'relative.pem' },
    { NODE_ENV: 'production' }, { HOST: '0.0.0.0' }, { HOST: 'public.example.invalid' }, { HOST: 'localhost' },
  ])('缺失、非法环境或证书主机不匹配均拒绝 #%#', (change: NodeJS.ProcessEnv): void => {
    expect((): unknown => loadTlsOptions({ ...fixture.environment, ...change })).toThrow(/^本机 HTTPS 配置无效$/);
  });
  it('丢失、目录、空文件、超大或损坏内容错误不输出路径和材料', (): void => {
    const file = join(fixture.root, 'invalid.pem');
    for (const path of [join(fixture.root, 'missing.pem'), fixture.root]) {
      expect((): unknown => loadTlsOptions({ ...fixture.environment, RULER_TLS_KEY_FILE: path })).toThrow(/^本机 HTTPS 配置无效$/);
    }
    for (const material of ['', 'fictional-private-material', 'x'.repeat(128 * 1024 + 1)]) {
      writeFileSync(file, material, { mode: 0o600 });
      expect((): unknown => loadTlsOptions({ ...fixture.environment, RULER_TLS_KEY_FILE: file })).toThrow(/^本机 HTTPS 配置无效$/);
    }
  });
  it('私钥不配对时拒绝启动，不降级 HTTP', (): void => {
    const other = tlsFixture();
    try { expect((): unknown => loadTlsOptions({ ...fixture.environment, RULER_TLS_KEY_FILE: other.key })).toThrow(/^本机 HTTPS 配置无效$/); }
    finally { other.close(); }
  });
  it.each([-2, 2])('未生效或过期证书拒绝（时钟偏移 %d 天）', (days: number): void => {
    const now = Date.now();
    jest.spyOn(Date, 'now').mockReturnValue(now + days * 86400_000);
    expect((): unknown => loadTlsOptions(fixture.environment)).toThrow(/^本机 HTTPS 配置无效$/);
  });
});
