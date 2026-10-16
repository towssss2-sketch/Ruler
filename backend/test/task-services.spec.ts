import { randomBytes, randomUUID } from 'node:crypto';
import { PrismaRepository } from '../src/prisma.repository';
import { EncryptionService } from '../src/encryption.service';
import { TaskViewService } from '../src/modules/task/task-view.service';
import { TaskWriteService } from '../src/modules/task/task-write.service';
import { TaskReadService } from '../src/modules/task/task-read.service';
import { PageInput } from '../src/modules/case/case-input';

describe('任务服务单元：错误路径', (): void => {
  const view = new TaskViewService(new EncryptionService(randomBytes(32)));
  it('守卫之后任务被删除时，事务复核仍拒绝更新和删除', async (): Promise<void> => {
    const tx = { $queryRaw: jest.fn().mockResolvedValue([{ id: randomUUID() }]), task: { findFirst: jest.fn().mockResolvedValue(null) } };
    const repository = { db: { $transaction: async (fn: (value: unknown) => Promise<unknown>): Promise<unknown> => fn(tx) } } as unknown as PrismaRepository;
    const service = new TaskWriteService(repository,view);
    await expect(service.update(randomUUID(),randomUUID(),randomUUID(),{ title: '虚构' })).rejects.toMatchObject({ status: 403 });
    await expect(service.remove(randomUUID(),randomUUID(),randomUUID())).rejects.toMatchObject({ status: 403 });
  });
  it('超出今日候选预算时明确失败，不返回被悄悄截断的优先级列表', async (): Promise<void> => {
    const tx = { task: { findMany: jest.fn().mockResolvedValue(Array.from({ length: 5001 },(): object => ({}))) } };
    const repository = { db: { $transaction: async (fn: (value: unknown) => Promise<unknown>): Promise<unknown> => fn(tx) } } as unknown as PrismaRepository;
    await expect(new TaskReadService(repository,view).today(randomUUID(),new PageInput())).rejects.toMatchObject({ status: 409 });
  });
});
