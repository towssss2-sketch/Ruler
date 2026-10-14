import { BadRequestException, Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiBody, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthPrincipal, CurrentUser } from '../auth/auth-decorators';
import { CaseAccessGuard } from './case-access.guard';
import { CaseInput, CaseQuery, PageInput, caseInput, dto } from './case-input';
import { CaseDetail, CaseSummary } from './case-view.service';
import { CaseReadService, CasePage } from './case-read.service';
import { CaseWriteService } from './case-write.service';
import { CaseDeleteService } from './case-delete.service';
import { CaseConflictService, ConflictPage } from './case-conflict.service';
import { CASE_BODY, caseListQueries, casePageQueries } from './case-openapi';

@ApiTags('案件管理') @ApiBearerAuth() @Controller('cases')
export class CaseController {
  constructor(private readonly read: CaseReadService, private readonly write: CaseWriteService,
    private readonly deletion: CaseDeleteService, private readonly conflicts: CaseConflictService) {}

  /** 校验创建 DTO 并绑定当前用户，禁止客户端指定 ownerId。 */
  @Post() @ApiOperation({ summary: '新建案件及当事人（事务）' })
  @ApiBody({ schema: { ...CASE_BODY, required: ['caseNo', 'cause', 'court', 'parties'] } })
  create(@CurrentUser() principal: AuthPrincipal, @Body() body: CaseInput): Promise<CaseSummary> {
    return this.write.create(principal.userId, caseInput(body, true));
  }

  /** 返回本人主办案件的筛选分页；协作组预留。 */
  @Get() @ApiOperation({ summary: '我的案件：搜索、筛选、分页与更新时间排序' })
  @caseListQueries()
  list(@CurrentUser() principal: AuthPrincipal, @Query() query: unknown): Promise<CasePage> {
    return this.read.list(principal.userId, dto(CaseQuery, query));
  }

  /** 每次经资源守卫核验归属后返回详情。 */
  @Get(':caseId') @UseGuards(CaseAccessGuard) @ApiOperation({ summary: '案件详情、当事人与文件/任务统计' })
  detail(@CurrentUser() principal: AuthPrincipal, @Param('caseId') id: string): Promise<CaseDetail> {
    return this.read.detail(principal.userId, id);
  }

  /** 部分更新案件；提供 parties 时按完整列表同步，省略的当事人软删除。 */
  @Patch(':caseId') @UseGuards(CaseAccessGuard) @ApiOperation({ summary: '更新案件与当事人' })
  @ApiBody({ schema: CASE_BODY })
  update(@CurrentUser() principal: AuthPrincipal, @Param('caseId') id: string, @Body() body: CaseInput): Promise<CaseSummary> {
    return this.write.update(principal.userId, id, caseInput(body, false));
  }

  /** 事务软删除，保留审计历史；法定期间与外部归集归属保护返回明确 409。 */
  @Delete(':caseId') @UseGuards(CaseAccessGuard) @ApiOperation({ summary: '软删除案件及关联记录' })
  remove(@CurrentUser() principal: AuthPrincipal, @Param('caseId') id: string): Promise<{ deleted: true }> {
    return this.deletion.remove(principal.userId, id);
  }

  /** 姓名模糊匹配本人历史案件；结果只提示人工复核，不判断法律利益冲突。 */
  @Post(':caseId/conflict-check') @HttpCode(200) @UseGuards(CaseAccessGuard)
  @ApiOperation({ summary: '利益冲突候选检查（相似度至少 0.6）' })
  @casePageQueries()
  conflictsCheck(@CurrentUser() principal: AuthPrincipal, @Param('caseId') id: string,
    @Query() query: unknown, @Body() body: unknown): Promise<ConflictPage> {
    // 无正文接口仍拒绝额外输入，避免调用者误以为可指定其他用户或阈值。
    caseConflictBody(body);
    return this.conflicts.check(principal.userId, id, dto(PageInput, query));
  }
}

/** 冲突检查没有可写正文，不接受用户/阈值覆盖。 */
function caseConflictBody(body: unknown): void {
  if (body !== undefined && (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).length > 0)) {
    throw new BadRequestException();
  }
}
