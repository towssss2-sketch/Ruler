import { randomBytes, randomUUID } from 'node:crypto';
import { Task } from '@prisma/client';
import { calendarDate, taskInput } from '../src/modules/task/task-input';
import { compareTasks, deadlineWindow, protectDeadline, todayDate } from '../src/modules/task/task-policy';
import { EncryptionService } from '../src/encryption.service';
import { TaskViewService } from '../src/modules/task/task-view.service';

describe('任务日期、状态和法定期间保护单元', (): void => {
  it.each(['2026-02-29', '2026-04-31', '0000-01-01', '2026-1-01', '2026-01-01T00:00:00Z', 'invalid'])(
    '拒绝无效日历日期 %s', (input: string): void => { expect((): Date => calendarDate(input)).toThrow(); });
  it('接受闰日，按北京时间午夜分日，不依赖主机日期', (): void => {
    expect(calendarDate('2028-02-29').toISOString()).toBe('2028-02-29T00:00:00.000Z');
    expect(todayDate(new Date('2026-12-31T15:59:59Z')).toISOString().slice(0, 10)).toBe('2026-12-31');
    expect(todayDate(new Date('2026-12-31T16:00:00Z')).toISOString().slice(0, 10)).toBe('2027-01-01');
  });
  it.each([{}, { title: null }, { title: ' ' }, { title: 'x', source: 'DEADLINE_RULE' },
    { title: 'x', deadlineType: 'OTHER' }, { title: 'x', completedAt: new Date() }, { title: 'x', description: '' },
    { title: 'x', status: null }, { title: 'x', isClientVisible: 'true' }])('拒绝空输入与额外字段 %#', (input): void => {
    expect((): unknown => taskInput(input, true)).toThrow();
  });
  it('部分更新可清空日期与描述；更新也禁止空对象', (): void => {
    expect(taskInput({ description: null, dueDate: null }, false)).toMatchObject({ description: null, dueDate: null });
    expect((): unknown => taskInput({}, false)).toThrow();
  });
  it('法定期间只允许状态切换，普通任务可编辑', (): void => {
    const record = { source: 'DEADLINE_RULE' } as Task;
    expect((): void => protectDeadline(record, { status: 'DONE' })).not.toThrow();
    expect((): void => protectDeadline(record, { title: '伪造' })).toThrow('专用复核');
    expect((): void => protectDeadline({ source: 'MANUAL' } as Task, { dueDate: null })).not.toThrow();
  });
  it('仅已确认期间可进窗口；损坏配置不生成确定性预警结果', (): void => {
    const today = calendarDate('2026-10-16');
    const record = { dueDate: calendarDate('2026-10-23'), deadlineConfirmedAt: new Date(),
      deadlineConfirmedById: randomUUID(), alertDays: [7, 3, 1] } as Task;
    expect(deadlineWindow(record, today)).toBe(true);
    expect(deadlineWindow({ ...record, dueDate: calendarDate('2026-10-24') }, today)).toBe(false);
    expect(deadlineWindow({ ...record, dueDate: null }, today)).toBe(false);
    expect(deadlineWindow({ ...record, deadlineConfirmedAt: null }, today)).toBe(false);
    expect(deadlineWindow({ ...record, deadlineConfirmedById: null }, today)).toBe(false);
    expect(deadlineWindow({ ...record, alertDays: {} }, today)).toBe(false);
    expect(deadlineWindow({ ...record, alertDays: [-1, 1.1, '7', 3651] }, today)).toBe(false);
  });
  it('优先级、日期和稳定 ID 排序；无日期排最后', (): void => {
    const today = calendarDate('2026-10-16');
    const make = (id: string, source: Task['source'], dueDate: Date | null): Task => ({ id, source, dueDate, createdAt: new Date(0) } as Task);
    const records = [make('z', 'MANUAL', null), make('today', 'MANUAL', today),
      make('overdue', 'MANUAL', calendarDate('2026-10-15')), make('deadline', 'DEADLINE_RULE', calendarDate('2026-10-20'))];
    expect(records.sort((a,b): number => compareTasks(today,a,b)).map((record): string => record.id)).toEqual(['deadline','overdue','today','z']);
    expect(compareTasks(today, make('a','MANUAL',today), make('b','MANUAL',today))).toBeLessThan(0);
  });
  it('描述加密省略、清空和错误 AAD；返回不包含软删除列', (): void => {
    const cipher = new EncryptionService(randomBytes(32)); const service = new TaskViewService(cipher); const id = randomUUID();
    expect(service.encrypt(undefined,id)).toBeUndefined(); expect(service.encrypt(null,id)).toBeNull();
    const encrypted = service.encrypt('虚构描述', id)!;
    const result = service.view({ id, description: encrypted, deletedAt: null } as Task);
    expect(result.description).toBe('虚构描述'); expect('deletedAt' in result).toBe(false);
    expect(service.view({ id, description: null } as Task).description).toBeNull();
    expect((): unknown => service.view({ id: randomUUID(), description: encrypted } as Task)).toThrow('解密失败');
  });
});
