import { Controller, Get, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CaseAccessGuard, ScopedRequest } from './case-access.guard';
import { AuthorizedScope } from './case-access.service';

/** 本期可验证权限的最小接口，不替代后续案件/文件/任务 CRUD。 */
@ApiTags('资源权限验证') @ApiBearerAuth() @UseGuards(CaseAccessGuard) @Controller()
export class ResourceAccessController {
  /** 返回守卫已验证的范围；不存在和无权限同样返回 403。 */
  @Get('cases/:caseId/access') @ApiOperation({ summary: '验证当前用户的案件 OWNER 权限' })
  caseAccess(@Req() request: ScopedRequest): AuthorizedScope { return request.resourceScope!; }

  /** 文件 ID 必须经实时反查父案件，再核验主办权限。 */
  @Get('documents/:documentId/access')
  documentAccess(@Req() request: ScopedRequest): AuthorizedScope { return request.resourceScope!; }

  /** 任务 ID 必须经实时反查父案件，再核验主办权限。 */
  @Get('tasks/:taskId/access')
  taskAccess(@Req() request: ScopedRequest): AuthorizedScope { return request.resourceScope!; }
}
