import { ForbiddenException, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Prisma, Task } from '@prisma/client';
import { BizException } from '../../biz-exception';
import { PrismaRepository } from '../../prisma.repository';
import { lockCase } from '../case/case-transaction';
import { calendarDate, TaskInput } from './task-input';
import { auditTask, protectDeadline } from './task-policy';
import { TaskView, TaskViewService } from './task-view.service';

@Injectable()
export class TaskWriteService {
  constructor(private readonly repository: PrismaRepository, private readonly view: TaskViewService) {}

  /** 事务新建手动任务，来源与完成时间由后端确定，同事务审计。 */
  async create(userId: string, caseId: string, input: TaskInput): Promise<TaskView> {
    return this.repository.db.$transaction(async (tx): Promise<TaskView> => {
      await lockCase(tx, userId, caseId, true);
      const id = randomUUID();
      const record = await tx.task.create({ data: { id, caseId, source: 'MANUAL', title: input.title!,
        description: this.view.encrypt(input.description, id), dueDate: input.dueDate ? calendarDate(input.dueDate) : null,
        status: input.status, isClientVisible: input.isClientVisible, completedAt: input.status === 'DONE' ? new Date() : null } });
      await auditTask(tx, userId, caseId, id, 'TASK_CREATED', Object.entries(input).filter(([,value]): boolean => value !== undefined).map(([key]): string => key));
      return this.view.view(record);
    });
  }

  /** 更新任务；完成重试保留首次完成时间，恢复待办清除完成时间，法定期间不可绕过复核。 */
  async update(userId: string, caseId: string, taskId: string, input: TaskInput): Promise<TaskView> {
    return this.repository.db.$transaction(async (tx): Promise<TaskView> => {
      await lockCase(tx, userId, caseId, true);
      const current = await this.active(tx, caseId, taskId);
      protectDeadline(current, input);
      const record = await tx.task.update({ where: { id: taskId }, data: { title: input.title,
        description: this.view.encrypt(input.description, taskId),
        dueDate: input.dueDate === undefined ? undefined : input.dueDate === null ? null : calendarDate(input.dueDate),
        status: input.status, isClientVisible: input.isClientVisible,
        completedAt: input.status === undefined ? undefined : input.status === 'DONE' ? current.completedAt ?? new Date() : null } });
      await auditTask(tx, userId, caseId, taskId, 'TASK_UPDATED', Object.entries(input).filter(([,value]): boolean => value !== undefined).map(([key]): string => key));
      return this.view.view(record);
    });
  }

  /** 软删除普通任务；法定期间任务始终拒绝删除，即使已经完成。 */
  async remove(userId: string, caseId: string, taskId: string): Promise<{ deleted: true }> {
    return this.repository.db.$transaction(async (tx): Promise<{ deleted: true }> => {
      await lockCase(tx, userId, caseId, true);
      const record = await this.active(tx, caseId, taskId);
      if (record.source === 'DEADLINE_RULE') throw new BizException(40911, '法定期间任务禁止删除，请标记完成', 409);
      await tx.task.update({ where: { id: taskId }, data: { deletedAt: new Date() } });
      await auditTask(tx, userId, caseId, taskId, 'TASK_DELETED', []);
      return { deleted: true };
    });
  }

  private async active(tx: Prisma.TransactionClient, caseId: string, id: string): Promise<Task> {
    const record = await tx.task.findFirst({ where: { id, caseId, deletedAt: null } });
    if (!record) throw new ForbiddenException();
    return record;
  }
}
