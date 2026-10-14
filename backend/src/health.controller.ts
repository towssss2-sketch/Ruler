import { Controller, Get } from '@nestjs/common';
import { HealthService, HealthStatus } from './health.service';

@Controller('health')
export class HealthController {
  constructor(private readonly service: HealthService) {}

  /** 无入参；返回进程存活状态。 */
  @Get()
  live(): HealthStatus {
    return this.service.live();
  }

  /** 无入参；数据库不可用时返回 503。 */
  @Get('ready')
  ready(): Promise<HealthStatus> {
    return this.service.ready();
  }
}
