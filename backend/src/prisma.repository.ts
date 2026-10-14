import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

/** 隔离 Prisma 访问；阶段 0 仅提供数据库连通性检查。 */
@Injectable()
export class PrismaRepository implements OnModuleDestroy {
  private readonly client = new PrismaClient();

  /** 提供同一生命周期内的 Prisma 客户端，供业务模块执行事务与实时权限查询。 */
  get db(): PrismaClient {
    return this.client;
  }

  /** 执行无业务数据的参数化查询；失败交给服务层转换。 */
  async checkConnection(): Promise<void> {
    await this.client.$queryRaw`SELECT 1`;
  }

  /** 关闭应用时释放数据库连接。 */
  async onModuleDestroy(): Promise<void> {
    await this.client.$disconnect();
  }
}
