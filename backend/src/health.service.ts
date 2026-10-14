import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { PrismaRepository } from './prisma.repository';

export interface HealthStatus {
  status: 'ok';
  stage: 0;
}

@Injectable()
export class HealthService {
  constructor(private readonly repository: PrismaRepository) {}

  /** 返回进程存活状态；不代表数据库或业务功能就绪。 */
  live(): HealthStatus {
    return { status: 'ok', stage: 0 };
  }

  /** 验证数据库连通性；失败返回固定消息，不泄露数据库错误。 */
  async ready(): Promise<HealthStatus> {
    try {
      await this.repository.checkConnection();
      return this.live();
    } catch {
      throw new ServiceUnavailableException('开发数据库暂不可用');
    }
  }
}
