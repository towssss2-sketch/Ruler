import { Body, CanActivate, Controller, ExecutionContext, Injectable, Param, ParseUUIDPipe, Post, UnauthorizedException, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthPrincipal, CurrentUser } from '../auth/auth-decorators';
import { CaseAccessService } from '../case/case-access.service';
import { ScopedRequest } from '../case/case-access.guard';
import { dto } from '../case/case-input';
import { DocumentView } from '../document/document-policy';
import { AssignInput } from './ingestion-assign-policy';
import { IngestionAssignService } from './ingestion-assign.service';

@Injectable()
export class IngestionAssignGuard implements CanActivate {
  constructor(private readonly access: CaseAccessService) {}
  /** assign 的案件来自严格 DTO，复用统一资源授权，事务中仍重新锁定校验。 */
  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<ScopedRequest>();
    if (!request.principal) throw new UnauthorizedException();
    const input = dto(AssignInput, request.body);
    request.resourceScope = await this.access.authorize(request.principal.userId, { caseId: input.caseId }, 'POST');
    return true;
  }
}

@ApiTags('材料归集') @ApiBearerAuth() @Controller('ingestion')
export class IngestionAssignController {
  constructor(private readonly service: IngestionAssignService) {}
  /** 人工分类与案件指派；不接收来源、对象键、文件名或自动生成任务指令。 */
  @Post(':id/assign') @UseGuards(IngestionAssignGuard)
  @ApiOperation({ summary: '将本人待定附件按指定分类归入本人主办案件' })
  assign(@CurrentUser() user: AuthPrincipal, @Param('id', new ParseUUIDPipe()) id: string,
    @Body() body: AssignInput): Promise<DocumentView> {
    return this.service.assign(user.userId, id, dto(AssignInput, body));
  }
}
