import { Module } from '@nestjs/common';
import { HealthController } from './health.controller';
import { HealthService } from './health.service';
import { PrismaRepository } from './prisma.repository';

@Module({
  controllers: [HealthController],
  providers: [HealthService, PrismaRepository],
})
export class AppModule {}
