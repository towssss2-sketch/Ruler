import { Module } from '@nestjs/common';
import { PrismaModule } from '../../prisma.module';
import { ResourceAccessModule } from '../case/resource-access.module';
import { StorageModule } from './storage/storage.module';
import { DocumentController } from './document.controller';
import { DocumentUploadService } from './document-upload.service';
import { DocumentRegisterService } from './document-register.service';
import { DocumentReadService } from './document-read.service';
import { DocumentWriteService } from './document-write.service';
import { DocumentCleanupService } from './document-cleanup.service';

@Module({ imports: [PrismaModule, ResourceAccessModule, StorageModule], controllers: [DocumentController],
  providers: [DocumentUploadService, DocumentRegisterService, DocumentReadService, DocumentWriteService, DocumentCleanupService],
  exports: [DocumentUploadService, DocumentRegisterService] })
export class DocumentModule {}
