import { Body, Controller, Header, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthPrincipal, CurrentUser } from '../../auth/auth-decorators';
import { emptyIngestionInput } from '../ingestion-input';
import { IngestionPreview, IngestionPreviewService } from './ingestion-preview.service';

@ApiTags('材料正文预览') @ApiBearerAuth() @Controller('ingestion')
export class IngestionPreviewController {
  constructor(private readonly service: IngestionPreviewService) {}

  /** 本人原件按需提取，不接受外部 URL、密钥、正文、分类或归属覆盖。 */
  @Post(':id/preview') @Header('Cache-Control', 'private, no-store')
  @ApiOperation({ summary: '提取本人 PDF/DOCX 正文与待确认分类建议（不自动归档）' })
  preview(@CurrentUser() user: AuthPrincipal, @Param('id', new ParseUUIDPipe()) id: string,
    @Body() body: unknown): Promise<IngestionPreview> {
    emptyIngestionInput(body);
    return this.service.preview(user.userId, id);
  }
}
