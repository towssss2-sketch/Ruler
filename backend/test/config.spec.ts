import { loadConfig } from '../src/config';

const fixture: NodeJS.ProcessEnv = {
  NODE_ENV: 'test', HOST: '127.0.0.1', PORT: '3000',
  DATABASE_URL: 'postgresql://localhost/ruler_test',
};

describe('开发配置', (): void => {
  it('接受显式开发配置', (): void => {
    expect(loadConfig(fixture).PORT).toBe(3000);
  });
  it('默认开发模式', (): void => {
    expect(loadConfig({ ...fixture, NODE_ENV: undefined }).NODE_ENV).toBe('development');
  });
  it.each(['0', '65536', 'not-a-port'])('拒绝非法端口 %s', (PORT: string): void => {
    expect((): void => { loadConfig({ ...fixture, PORT }); }).toThrow('PORT');
  });
  it('拒绝生产启动，避免基座被当成生产系统', (): void => {
    expect((): void => { loadConfig({ ...fixture, NODE_ENV: 'production' }); }).toThrow('NODE_ENV');
  });
  it('配置错误不泄露连接串', (): void => {
    const invalid = 'https://test.invalid/fictional-sensitive-input';
    try {
      loadConfig({ ...fixture, DATABASE_URL: invalid });
      throw new Error('应拒绝配置');
    } catch (error: unknown) {
      expect(error).toBeInstanceOf(Error);
      expect((error as Error).message).toBe('环境配置无效：DATABASE_URL');
      expect((error as Error).message).not.toContain(invalid);
    }
  });
  it('缺失配置列出字段，不输出值', (): void => {
    expect((): void => { loadConfig({}); }).toThrow('HOST, PORT, DATABASE_URL');
  });
});
