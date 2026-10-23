import { Module } from '@nestjs/common';
import { HealthController } from './health.controller';
import { HealthService } from './health.service';
import { PrismaModule } from './prisma.module';
import { AuthModule } from './modules/auth/auth.module';
import { ResourceAccessModule } from './modules/case/resource-access.module';
import { DocumentModule } from './modules/document/document.module';
import { TaskModule } from './modules/task/task.module';
import { IngestionModule } from './modules/ingestion/ingestion.module';

@Module({
  imports: [PrismaModule, AuthModule, ResourceAccessModule, DocumentModule, TaskModule, IngestionModule],
  controllers: [HealthController],
  providers: [HealthService],
})
export class AppModule {}
