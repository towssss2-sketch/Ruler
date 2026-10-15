import { Module } from '@nestjs/common';
import { PrismaModule } from '../../prisma.module';
import { CaseAccessGuard } from './case-access.guard';
import { CaseAccessService } from './case-access.service';
import { ResourceAccessController } from './resource-access.controller';
import { CaseController } from './case.controller';
import { CaseReadService } from './case-read.service';
import { CaseWriteService } from './case-write.service';
import { CaseDeleteService } from './case-delete.service';
import { CaseConflictService } from './case-conflict.service';
import { CasePartiesService } from './case-parties.service';
import { CaseViewService } from './case-view.service';
import { EncryptionService } from '../../encryption.service';
import { configuredCipher } from '../../encryption-config';

@Module({ imports: [PrismaModule], controllers: [ResourceAccessController, CaseController],
  providers: [CaseAccessGuard, CaseAccessService, CaseReadService, CaseWriteService, CaseDeleteService,
    CaseConflictService, CasePartiesService, CaseViewService,
    { provide: EncryptionService, useFactory: (): EncryptionService => configuredCipher(process.env) }],
  exports: [CaseAccessGuard, CaseAccessService] })
export class ResourceAccessModule {}
