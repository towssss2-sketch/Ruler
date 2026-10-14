import { Module } from '@nestjs/common';
import { PrismaModule } from '../../prisma.module';
import { CaseAccessGuard } from './case-access.guard';
import { CaseAccessService } from './case-access.service';
import { ResourceAccessController } from './resource-access.controller';

@Module({ imports: [PrismaModule], controllers: [ResourceAccessController], providers: [CaseAccessGuard, CaseAccessService] })
export class ResourceAccessModule {}
