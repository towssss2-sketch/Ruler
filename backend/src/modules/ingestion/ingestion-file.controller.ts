import { Body, Controller, Get, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsUUID } from 'class-validator';
import { AuthPrincipal, CurrentUser } from '../auth/auth-decorators';
import { dto } from '../case/case-input';
import { FileUploadInput } from '../document/document-input';
import { SignedTransfer } from '../document/storage/storage.service';
import { FileReceipt, IngestionFileView } from './ingestion-file-policy';
import { IngestionFileUploadService, IngestionOffer } from './ingestion-file-upload.service';
import { IngestionFileRegisterService } from './ingestion-file-register.service';
import { IngestionFileReadService } from './ingestion-file-read.service';

export class CompleteIngestionFileInput { @IsUUID() uploadId!: string }

@ApiTags('材料文件暂存') @ApiBearerAuth() @Controller('ingestion')
export class IngestionFileController {
  constructor(private readonly uploads: IngestionFileUploadService, private readonly register: IngestionFileRegisterService,
    private readonly read: IngestionFileReadService) {}

  /** 手动接收微信文件的准备步骤；尚未进入待定区，不接收案件或分类参数。 */
  @Post('files/presign') @ApiOperation({ summary: '无需案件的文件暂存上传申请' })
  presign(@CurrentUser() user: AuthPrincipal, @Body() body: FileUploadInput): Promise<IngestionOffer> {
    return this.uploads.presign(user.userId, dto(FileUploadInput, body));
  }

  /** 核验实际对象后完成接收；此接口不信任客户端提交的 SHA 或存储键。 */
  @Post('files') @ApiOperation({ summary: '完成文件接收，实际内容去重后进入待定区' })
  complete(@CurrentUser() user: AuthPrincipal, @Body() body: CompleteIngestionFileInput): Promise<FileReceipt> {
    return this.register.register(user.userId, dto(CompleteIngestionFileInput, body).uploadId);
  }

  /** 附件元数据只向当前用户开放。 */
  @Get(':id/file') @ApiOperation({ summary: '本人归集附件资料' })
  metadata(@CurrentUser() user: AuthPrincipal, @Param('id', new ParseUUIDPipe()) id: string): Promise<IngestionFileView> {
    return this.read.metadata(user.userId, id);
  }

  /** 下载链接最长十分钟，不提供永久公开路径。 */
  @Get(':id/file/download') @ApiOperation({ summary: '下载本人归集原件（短效签名）' })
  download(@CurrentUser() user: AuthPrincipal, @Param('id', new ParseUUIDPipe()) id: string): Promise<SignedTransfer> {
    return this.read.download(user.userId, id);
  }
}
