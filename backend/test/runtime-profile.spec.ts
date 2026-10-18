import { loadRuntimeProfile } from '../src/runtime-profile';

describe('本机隔离模式配置', (): void => {
  const valid = { RULER_RUNTIME_PROFILE: 'restricted-local', NODE_ENV: 'test', HOST: '127.0.0.1',
    RULER_TLS_CERT_FILE: '/fictional/cert.pem', RULER_TLS_KEY_FILE: '/fictional/key.pem' };
  it('未指定时保持开发模式；显式开发模式兼容原配置', (): void => {
    expect(loadRuntimeProfile({})).toBe('development');
    expect(loadRuntimeProfile({ RULER_RUNTIME_PROFILE: 'development' })).toBe('development');
  });
  it('隔离模式要求本机、非生产和完整 TLS 配置', (): void => {
    expect(loadRuntimeProfile(valid)).toBe('restricted-local');
    expect(loadRuntimeProfile({ ...valid, NODE_ENV: 'development', HOST: 'localhost' })).toBe('restricted-local');
  });
  it.each([
    { RULER_RUNTIME_PROFILE: '' }, { RULER_RUNTIME_PROFILE: 'restricted' }, { RULER_RUNTIME_PROFILE: 'production' },
    { NODE_ENV: 'production' }, { NODE_ENV: undefined }, { HOST: '0.0.0.0' }, { HOST: 'public.example.invalid' },
    { RULER_TLS_CERT_FILE: undefined }, { RULER_TLS_KEY_FILE: undefined }, { RULER_TLS_KEY_FILE: '' },
  ])('非法配置拒绝，不回落为开发模式 #%#', (change: NodeJS.ProcessEnv): void => {
    expect((): unknown => loadRuntimeProfile({ ...valid, ...change })).toThrow(/^运行模式配置无效$/);
  });
});
