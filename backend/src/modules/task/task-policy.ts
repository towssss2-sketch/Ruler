import { Prisma, Task } from '@prisma/client';
import { BizException } from '../../biz-exception';
import { calendarDate, TaskInput } from './task-input';

/** 北京时间的日历日，不依赖执行主机时区。 */
export function todayDate(now: Date): Date {
  return calendarDate(new Date(now.getTime() + 8 * 3600000).toISOString().slice(0, 10));
}

/** 法定期间通过专用确认流程维护；普通接口仅允许更改完成状态。 */
export function protectDeadline(record: Task, input: TaskInput): void {
  if (record.source === 'DEADLINE_RULE' && Object.entries(input).some(([key, value]): boolean => key !== 'status' && value !== undefined)) {
    throw new BizException(40910, '法定期间仅允许标记完成或恢复待办，其他变更须走专用复核流程', 409);
  }
}

/** 本次不计算法定期限；只使用已确认且进入预警窗口的已有记录。 */
export function deadlineWindow(record: Task, today: Date): boolean {
  if (!record.dueDate || !record.deadlineConfirmedAt || !record.deadlineConfirmedById) return false;
  if (!Array.isArray(record.alertDays)) return false;
  const days = record.alertDays.filter((value): value is number => typeof value === 'number'
    && Number.isInteger(value) && value >= 0 && value <= 3650);
  if (days.length === 0) return false;
  const remaining = Math.round((record.dueDate.getTime() - today.getTime()) / 86400000);
  return remaining <= Math.max(...days);
}

/** 今日排序：法定期间、逾期、今日到期、其他；组内按截止日期、创建时间与 ID 稳定排序。 */
export function compareTasks(today: Date, left: Task, right: Task): number {
  const rank = (task: Task): number => task.source === 'DEADLINE_RULE' ? 0
    : task.dueDate && task.dueDate < today ? 1 : task.dueDate?.getTime() === today.getTime() ? 2 : 3;
  return rank(left) - rank(right) || (left.dueDate?.getTime() ?? Infinity) - (right.dueDate?.getTime() ?? Infinity)
    || left.createdAt.getTime() - right.createdAt.getTime() || left.id.localeCompare(right.id);
}

/** 审计仅写变更字段名和状态，不写标题、描述或日期内容。 */
export async function auditTask(tx: Prisma.TransactionClient, userId: string, caseId: string,
  taskId: string, action: string, fields: string[]): Promise<void> {
  await tx.auditLog.create({ data: { userId, caseId, resourceType: 'Task', resourceId: taskId, action, detail: { fields } } });
}
