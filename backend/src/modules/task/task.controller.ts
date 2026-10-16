import { Body, Controller, Delete, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthPrincipal, CurrentUser } from '../auth/auth-decorators';
import { CaseAccessGuard, ScopedRequest } from '../case/case-access.guard';
import { dto, PageInput } from '../case/case-input';
import { TaskInput, taskInput, TaskQuery } from './task-input';
import { TaskReadService, TaskPage, TodayPage } from './task-read.service';
import { TaskWriteService } from './task-write.service';
import { TaskView } from './task-view.service';

@ApiTags('工作任务') @ApiBearerAuth() @Controller()
export class TaskController {
  constructor(private readonly read: TaskReadService, private readonly write: TaskWriteService) {}

  /** 校验 DTO 并绑定当前操作者，不能伪造来源或确认状态。 */
  @Post('cases/:caseId/tasks') @UseGuards(CaseAccessGuard) @ApiOperation({ summary: '新增手动工作任务' })
  create(@CurrentUser() user: AuthPrincipal, @Param('caseId') id: string, @Body() body: TaskInput): Promise<TaskView> {
    return this.write.create(user.userId, id, taskInput(body, true));
  }

  /** 每次经实时资源守卫及事务复核，分页列出案件任务。 */
  @Get('cases/:caseId/tasks') @UseGuards(CaseAccessGuard) @ApiOperation({ summary: '案件任务按来源和状态筛选' })
  list(@CurrentUser() user: AuthPrincipal, @Param('caseId') id: string, @Query() query: unknown): Promise<TaskPage> {
    return this.read.list(user.userId, id, dto(TaskQuery, query));
  }

  /** 跨本人主办案件汇总，服务查询本身限制归属；不得使用路径守卫假造案件范围。 */
  @Get('tasks/today') @ApiOperation({ summary: '北京时间今日到期、逾期与已确认法定期间预警窗口任务' })
  today(@CurrentUser() user: AuthPrincipal, @Query() query: unknown): Promise<TodayPage> {
    return this.read.today(user.userId, dto(PageInput, query));
  }

  /** 已解析父案件的任务更新；只允许法定期间任务切换状态。 */
  @Patch('tasks/:taskId') @UseGuards(CaseAccessGuard) @ApiOperation({ summary: '编辑任务或切换完成状态' })
  update(@CurrentUser() user: AuthPrincipal, @Param('taskId') id: string, @Req() request: ScopedRequest,
    @Body() body: TaskInput): Promise<TaskView> {
    return this.write.update(user.userId, request.resourceScope!.caseId, id, taskInput(body, false));
  }

  /** 软删除常规任务，拒绝删除法定期间记录。 */
  @Delete('tasks/:taskId') @UseGuards(CaseAccessGuard) @ApiOperation({ summary: '软删除任务；法定期间禁止删除' })
  remove(@CurrentUser() user: AuthPrincipal, @Param('taskId') id: string, @Req() request: ScopedRequest): Promise<{ deleted: true }> {
    return this.write.remove(user.userId, request.resourceScope!.caseId, id);
  }
}
