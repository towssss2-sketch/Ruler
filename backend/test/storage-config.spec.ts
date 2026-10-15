import { loadStorageConfig } from '../src/modules/document/storage/storage-config';
import { configuredStorage, StorageModule } from '../src/modules/document/storage/storage.module';
import { S3Driver } from '../src/modules/document/storage/s3-driver';
import { OssDriver } from '../src/modules/document/storage/oss-driver';
import { minioConfig, ossConfig } from './storage/fixtures';
import { Test } from '@nestjs/testing';
import { StorageService } from '../src/modules/document/storage/storage.service';

function localEnvironment(): NodeJS.ProcessEnv {
  const c = minioConfig();
  return { NODE_ENV: 'test', STORAGE_DRIVER: c.driver, STORAGE_BUCKET: c.bucket, STORAGE_REGION: c.region,
    STORAGE_SIGNED_URL_TTL_SECONDS: '600', MINIO_ENDPOINT: c.endpoint, MINIO_ROOT_USER: c.accessKeyId, MINIO_ROOT_PASSWORD: c.secretAccessKey };
}
function cloudEnvironment(): NodeJS.ProcessEnv {
  const c = ossConfig();
  return { NODE_ENV: 'test', STORAGE_DRIVER: c.driver, STORAGE_BUCKET: c.bucket, STORAGE_REGION: c.region,
    STORAGE_SIGNED_URL_TTL_SECONDS: '600', OSS_ENDPOINT: c.endpoint, OSS_ACCESS_KEY_ID: c.accessKeyId,
    OSS_ACCESS_KEY_SECRET: c.accessKeySecret, OSS_SECURITY_TOKEN: c.securityToken };
}

describe('存储配置与驱动选择', (): void => {
  it('根据环境选择 MinIO 或原生 OSS，生命周期关闭只释放自身资源', (): void => {
    const minio = configuredStorage(localEnvironment());
    const oss = configuredStorage(cloudEnvironment());
    expect(minio instanceof S3Driver).toBe(true);
    expect(oss instanceof OssDriver).toBe(true);
    const close = jest.spyOn(minio, 'close');
    new StorageModule(minio).onModuleDestroy();
    expect(close).toHaveBeenCalledTimes(1);
    oss.close();
  });
  it('配置不完整和十分钟以上签名立即拒绝，不输出密钥值', (): void => {
    expect((): unknown => loadStorageConfig({})).toThrow('文件存储配置无效');
    expect((): unknown => loadStorageConfig({ ...localEnvironment(), STORAGE_SIGNED_URL_TTL_SECONDS: '601' })).toThrow();
    expect((): unknown => loadStorageConfig({ ...localEnvironment(), MINIO_ROOT_PASSWORD: '' })).toThrow('开发存储配置无效');
    expect((): unknown => loadStorageConfig({ ...cloudEnvironment(), OSS_ACCESS_KEY_SECRET: '' })).toThrow('OSS 存储配置无效');
    expect((): unknown => loadStorageConfig({ ...cloudEnvironment(), STORAGE_REGION: 'bad' })).toThrow();
  });
  it.each(['http://example.invalid:9000', 'ftp://127.0.0.1:9000', 'http://127.0.0.1:9000/path',
    'http://user:fictional@127.0.0.1:9000', 'http://127.0.0.1:9000?token=fictional', 'http://127.0.0.1:9000#x'])(
    '拒绝非本机或携带路径/凭据的开发端点 #%#', (endpoint: string): void => {
      expect((): unknown => loadStorageConfig({ ...localEnvironment(), MINIO_ENDPOINT: endpoint })).toThrow();
    });
  it('生产配置禁止使用 MinIO 开发凭据；OSS 限定官方 HTTPS 与匹配区域', (): void => {
    expect((): unknown => loadStorageConfig({ ...localEnvironment(), NODE_ENV: 'production' })).toThrow();
    for (const endpoint of ['http://oss-cn-hangzhou.aliyuncs.com', 'https://oss-cn-shanghai.aliyuncs.com',
      'https://example.invalid', 'https://oss-cn-hangzhou.aliyuncs.com:9000']) {
      expect((): unknown => loadStorageConfig({ ...cloudEnvironment(), OSS_ENDPOINT: endpoint })).toThrow('OSS 存储端点无效');
    }
    expect(loadStorageConfig({ ...cloudEnvironment(), NODE_ENV: 'production', OSS_SECURITY_TOKEN: undefined }).driver).toBe('oss');
  });
});

describe('存储端口的 Nest 注入', (): void => {
  it('业务通过抽象端口取得驱动，模块关闭释放连接', async (): Promise<void> => {
    const environment = localEnvironment();
    const saved = Object.fromEntries(Object.keys(environment).map((key): [string, string | undefined] => [key, process.env[key]]));
    Object.assign(process.env, environment);
    try {
      const module = await Test.createTestingModule({ imports: [StorageModule] }).compile();
      const storage = module.get(StorageService);
      const close = jest.spyOn(storage, 'close');
      expect(storage instanceof S3Driver).toBe(true);
      await module.close();
      expect(close).toHaveBeenCalledTimes(1);
    } finally {
      for (const [key, value] of Object.entries(saved)) {
        if (value === undefined) delete process.env[key]; else process.env[key] = value;
      }
    }
  });
});
