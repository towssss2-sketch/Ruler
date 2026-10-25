import { Body, CanActivate, Controller, ExecutionContext, Get, Injectable, Param, ParseUUIDPipe, Post, UnauthorizedException, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthPrincipal, CurrentUser } from '../auth/auth-decorators';
import { CaseAccessService } from '../case/case-access.service';
import { ScopedRequest } from '../case/case-access.guard';
import { dto } from '../case/case-input';
import { ArchiveView, IngestionArchiveService, WithdrawInput, WithdrawReceipt } from './ingestion-archive.service';

@Injectable()
export class IngestionWithdrawGuard implements CanActivate {
  constructor(private readonly access: CaseAccessService) {}
  /** 复用统一案件授权；文档身份由事务校验，允许已完成撤回的幂等重试。 */
  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<ScopedRequest>();
    if (!request.principal) throw new UnauthorizedException();
    const input = dto(WithdrawInput, request.body);
    request.resourceScope = await this.access.authorize(request.principal.userId, { caseId: input.caseId }, 'POST');
    return true;
  }
}

@ApiTags('材料归集') @ApiBearerAuth() @Controller('ingestion')
export class IngestionArchiveController {
  constructor(private readonly service: IngestionArchiveService) {}
  /** 当前归档去向；按本人材料和当前案件归属查询，不返回历史敏感信息。 */
  @Get(':id/assignment') @ApiOperation({ summary: '查看当前归档案件和分类' })
  locate(@CurrentUser() user: AuthPrincipal, @Param('id', new ParseUUIDPipe()) id: string): Promise<ArchiveView> {
    return this.service.locate(user.userId, id);
  }
  /** 严格绑定本次文档，不自动撤回后续重新归档的材料。 */
  @Post(':id/withdraw') @UseGuards(IngestionWithdrawGuard) @ApiOperation({ summary: '撤回本次归档至待定区' })
  withdraw(@CurrentUser() user: AuthPrincipal, @Param('id', new ParseUUIDPipe()) id: string,
    @Body() body: WithdrawInput): Promise<WithdrawReceipt> {
    return this.service.withdraw(user.userId, id, dto(WithdrawInput, body));
  }
}
