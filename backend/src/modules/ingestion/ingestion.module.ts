import { Module } from '@nestjs/common';
import { PrismaModule } from '../../prisma.module';
import { EncryptionService } from '../../encryption.service';
import { configuredCipher } from '../../encryption-config';
import { IngestionController } from './ingestion.controller';
import { IngestionService } from './ingestion.service';
import { IngestionViewService } from './ingestion-view.service';

@Module({ imports: [PrismaModule], controllers: [IngestionController], providers: [IngestionService, IngestionViewService,
  { provide: EncryptionService, useFactory: (): EncryptionService => configuredCipher(process.env) }] })
export class IngestionModule {}
