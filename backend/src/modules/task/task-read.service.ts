import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { BizException } from '../../biz-exception';
import { PrismaRepository } from '../../prisma.repository';
import { lockCase } from '../case/case-transaction';
import { PageInput } from '../case/case-input';
import { TaskQuery } from './task-input';
import { compareTasks, deadlineWindow, todayDate } from './task-policy';
import { TaskView, TaskViewService } from './task-view.service';

export interface TaskPage { items: TaskView[]; total: number; page: number; pageSize: number }
export type TodayTaskView = TaskView & { caseNo: string; court: string };
export interface TodayPage extends TaskPage { items: TodayTaskView[]; date: string; timeZone: 'Asia/Shanghai' }

@Injectable()
export class TaskReadService {
  constructor(private readonly repository: PrismaRepository, private readonly view: TaskViewService) {}

  /** 按来源、状态分页列出未删除任务；锁内复核案件权限后才解密。 */
  async list(userId: string, caseId: string, query: TaskQuery): Promise<TaskPage> {
    return this.repository.db.$transaction(async (tx): Promise<TaskPage> => {
      await lockCase(tx, userId, caseId, false);
      const where = { caseId, deletedAt: null, source: query.source, status: query.status };
      const page = Number(query.page); const pageSize = Number(query.pageSize);
      const total = await tx.task.count({ where });
      const records = await tx.task.findMany({ where, orderBy: [{ dueDate: { sort: 'asc', nulls: 'last' } },
        { createdAt: 'asc' }, { id: 'asc' }], skip: (page - 1) * pageSize, take: pageSize });
      return { items: records.map((record): TaskView => this.view.view(record)), total, page, pageSize };
    });
  }

  /** 北京时间今日未完成汇总；法定期间只读取已确认数据，不自动计算或确认日期。 */
  async today(userId: string, query: PageInput): Promise<TodayPage> {
    const today = todayDate(new Date());
    return this.repository.db.$transaction(async (tx): Promise<TodayPage> => {
      const records = await tx.task.findMany({ where: { deletedAt: null, status: 'TODO',
        case: { ownerId: userId, deletedAt: null }, OR: [{ source: { not: 'DEADLINE_RULE' }, dueDate: { lte: today } },
          { source: 'DEADLINE_RULE', deadlineConfirmedAt: { not: null }, deadlineConfirmedById: { not: null },
            dueDate: { lte: new Date(today.getTime() + 3650 * 86400000) } }] }, take: 5001,
        include: { case: { select: { caseNo: true, court: true } } } });
      // 不悄悄截断优先级结果；超出处理预算明确失败，后续可改为专用数据库视图。
      if (records.length > 5000) throw new BizException(40912, '今日任务候选过多，请先按案件处理', 409);
      const selected = records.filter((record): boolean => record.source !== 'DEADLINE_RULE' || deadlineWindow(record, today))
        .sort((left, right): number => compareTasks(today, left, right));
      const page = Number(query.page); const pageSize = Number(query.pageSize);
      return { items: selected.slice((page - 1) * pageSize, page * pageSize).map((record): TodayTaskView => {
        const { case: parent, ...task } = record;
        return { ...this.view.view(task), caseNo: parent.caseNo, court: parent.court };
      }),
        total: selected.length, page, pageSize, date: today.toISOString().slice(0, 10), timeZone: 'Asia/Shanghai' };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead });
  }
}
