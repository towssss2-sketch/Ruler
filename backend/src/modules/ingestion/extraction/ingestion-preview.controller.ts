import { Body, Controller, Get, Header, Param, ParseUUIDPipe, Post, Req } from '@nestjs/common';
import { Request } from 'express';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthPrincipal, CurrentUser } from '../../auth/auth-decorators';
import { emptyIngestionInput } from '../ingestion-input';
import { IngestionPreview, IngestionPreviewService } from './ingestion-preview.service';

import { PreviewAttemptService } from './preview-attempt.service';
import { PreviewAttemptPage } from './preview-attempt-view';
import { previewAttemptQuery } from './preview-attempt-input';

@ApiTags('材料正文预览') @ApiBearerAuth() @Controller('ingestion')
export class IngestionPreviewController {
  constructor(private readonly service: IngestionPreviewService, private readonly attempts: PreviewAttemptService) {}

  /** 查看历史不会启动解析或自动重试；已过租期的尝试显示中断。 */
  @Get(':id/preview-attempts') @Header('Cache-Control', 'private, no-store')
  @ApiOperation({ summary: '查看本人附件提取记录，按开始时间倒序分页；不含正文' })
  history(@CurrentUser() user: AuthPrincipal, @Param('id', new ParseUUIDPipe()) id: string,
    @Req() request: Request): Promise<PreviewAttemptPage> {
    return this.attempts.history(user.userId, id, previewAttemptQuery(request.originalUrl));
  }

  /** 本人原件按需提取，不接受外部 URL、密钥、正文、分类或归属覆盖。 */
  @Post(':id/preview') @Header('Cache-Control', 'private, no-store')
  @ApiOperation({ summary: '提取本人 PDF/DOCX 正文与待确认分类建议（不自动归档）' })
  preview(@CurrentUser() user: AuthPrincipal, @Param('id', new ParseUUIDPipe()) id: string,
    @Body() body: unknown): Promise<IngestionPreview> {
    emptyIngestionInput(body);
    return this.service.preview(user.userId, id);
  }
}
