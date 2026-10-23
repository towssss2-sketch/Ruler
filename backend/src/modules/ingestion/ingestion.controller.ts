import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthPrincipal, CurrentUser } from '../auth/auth-decorators';
import { dto, PageInput } from '../case/case-input';
import { emptyIngestionInput, textIngestionInput, TextIngestionInput } from './ingestion-input';
import { IngestionService } from './ingestion.service';
import { IngestionDetail, IngestionPage, IngestionReceipt } from './ingestion-view.service';

@ApiTags('材料归集') @ApiBearerAuth() @Controller('ingestion')
export class IngestionController {
  constructor(private readonly service: IngestionService) {}

  /** 微信文字的手动转发入口；暂不接收附件，不访问正文中的链接。 */
  @Post('wechat') @ApiOperation({ summary: '手动转发微信文字到待定区（尚不接收文件）' })
  receive(@CurrentUser() user: AuthPrincipal, @Body() body: TextIngestionInput): Promise<IngestionReceipt> {
    return this.service.receive(user.userId, textIngestionInput(body).rawContent);
  }

  /** 当前登录用户的待定记录，归属约束由服务端查询强制执行。 */
  @Get('pending') @ApiOperation({ summary: '本人的待定材料列表' })
  pending(@CurrentUser() user: AuthPrincipal, @Query() query: unknown): Promise<IngestionPage> {
    return this.service.list(user.userId, dto(PageInput, query), true);
  }

  /** 历史包含忽略状态，忽略不删除原始材料。 */
  @Get('logs') @ApiOperation({ summary: '本人的归集历史' })
  logs(@CurrentUser() user: AuthPrincipal, @Query() query: unknown): Promise<IngestionPage> {
    return this.service.list(user.userId, dto(PageInput, query), false);
  }

  /** 读取已授权的原始文字；不提供内部对象键或签名字段。 */
  @Get(':id') @ApiOperation({ summary: '查看本人归集记录原文' })
  detail(@CurrentUser() user: AuthPrincipal, @Param('id', new ParseUUIDPipe()) id: string): Promise<IngestionDetail> {
    return this.service.detail(user.userId, id);
  }

  /** 只接收空对象，避免忽略动作隐式改变归属或 AI 结果。 */
  @Post(':id/ignore') @ApiOperation({ summary: '忽略本人待定材料；保留归集历史' })
  ignore(@CurrentUser() user: AuthPrincipal, @Param('id', new ParseUUIDPipe()) id: string,
    @Body() body: unknown): Promise<{ ignored: true }> {
    emptyIngestionInput(body);
    return this.service.ignore(user.userId, id);
  }
}
