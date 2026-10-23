import { Module } from '@nestjs/common';
import { PrismaModule } from '../../prisma.module';
import { EncryptionService } from '../../encryption.service';
import { configuredCipher } from '../../encryption-config';
import { IngestionController } from './ingestion.controller';
import { IngestionService } from './ingestion.service';
import { IngestionViewService } from './ingestion-view.service';

import { StorageModule } from '../document/storage/storage.module';
import { IngestionFileController } from './ingestion-file.controller';
import { IngestionFileUploadService } from './ingestion-file-upload.service';
import { IngestionFileRegisterService } from './ingestion-file-register.service';
import { IngestionFileReadService } from './ingestion-file-read.service';
import { IngestionFileCleanupService } from './ingestion-file-cleanup.service';

@Module({ imports: [PrismaModule, StorageModule], controllers: [IngestionController, IngestionFileController],
  providers: [IngestionService, IngestionViewService, IngestionFileUploadService, IngestionFileRegisterService,
    IngestionFileReadService, IngestionFileCleanupService,
  { provide: EncryptionService, useFactory: (): EncryptionService => configuredCipher(process.env) }] })
export class IngestionModule {}
