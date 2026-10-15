import { Inject, Module, OnModuleDestroy } from '@nestjs/common';
import { loadStorageConfig } from './storage-config';
import { OssDriver } from './oss-driver';
import { S3Driver } from './s3-driver';
import { StorageService } from './storage.service';

/** 由环境选择实现，返回供应商无关端口；没有默认云凭据或自动创建真实桶。 */
export function configuredStorage(environment: NodeJS.ProcessEnv): StorageService {
  const config = loadStorageConfig(environment);
  return config.driver === 'minio' ? new S3Driver(config) : new OssDriver(config);
}

@Module({ providers: [{ provide: StorageService, useFactory: (): StorageService => configuredStorage(process.env) }],
  exports: [StorageService] })
export class StorageModule implements OnModuleDestroy {
  constructor(@Inject(StorageService) private readonly storage: StorageService) {}
  /** 应用关闭时释放当前存储实例；不改动对象或数据库。 */
  onModuleDestroy(): void { this.storage.close(); }
}
