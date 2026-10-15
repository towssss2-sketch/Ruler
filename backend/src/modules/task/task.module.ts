import { Module } from '@nestjs/common';
import { PrismaModule } from '../../prisma.module';
import { EncryptionService } from '../../encryption.service';
import { configuredCipher } from '../../encryption-config';
import { ResourceAccessModule } from '../case/resource-access.module';
import { TaskController } from './task.controller';
import { TaskReadService } from './task-read.service';
import { TaskWriteService } from './task-write.service';
import { TaskViewService } from './task-view.service';

@Module({ imports: [PrismaModule, ResourceAccessModule], controllers: [TaskController],
  providers: [TaskReadService, TaskWriteService, TaskViewService,
    { provide: EncryptionService, useFactory: (): EncryptionService => configuredCipher(process.env) }] })
export class TaskModule {}
