import { BadRequestException, Controller, Get, Header, Param, ParseUUIDPipe, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Request } from 'express';
import { AuthPrincipal, CurrentUser } from '../../auth/auth-decorators';
import { PreviewClassificationService, PreviewClassificationView } from './preview-classification.service';

@ApiTags('材料分类记录') @ApiBearerAuth() @Controller('ingestion')
export class PreviewClassificationController {
  constructor(private readonly service: PreviewClassificationService) {}

  /** 指定历史尝试只读；不接受分类、用户或规则覆盖，不缓存结果。 */
  @Get(':id/preview-attempts/:attemptId/classification') @Header('Cache-Control', 'private, no-store')
  @ApiOperation({ summary: '读取本人附件指定提取记录的规则分类，仍需人工确认' })
  read(@CurrentUser() user: AuthPrincipal, @Param('id', new ParseUUIDPipe()) id: string,
    @Param('attemptId', new ParseUUIDPipe()) attemptId: string, @Req() request: Request): Promise<PreviewClassificationView> {
    if (new URLSearchParams(request.originalUrl.split('?')[1] ?? '').size) throw new BadRequestException();
    return this.service.read(user.userId, id, attemptId);
  }
}
