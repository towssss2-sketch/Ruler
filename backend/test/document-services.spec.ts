import { randomUUID } from 'node:crypto';
import { Prisma } from '@prisma/client';
import { PrismaRepository } from '../src/prisma.repository';
import { StorageService } from '../src/modules/document/storage/storage.service';
import { DocumentCleanupService } from '../src/modules/document/document-cleanup.service';
import { activeDocument, lockDocumentOwner, uploadTicket, validateOrigin } from '../src/modules/document/document-transaction';

describe('文件服务单元：事务内授权复核', (): void => {
  it('父案件有效但所有者已停用时拒绝继续', async (): Promise<void> => {
    const tx = { $queryRaw: jest.fn().mockResolvedValue([{ id: randomUUID() }]),
      case: { findUniqueOrThrow: jest.fn().mockResolvedValue({ ownerId: randomUUID() }) },
      user: { findFirst: jest.fn().mockResolvedValue(null) } } as unknown as Prisma.TransactionClient;
    await expect(lockDocumentOwner(tx, randomUUID(), randomUUID())).rejects.toMatchObject({ status: 403 });
  });
  it('守卫通过之后消失的文档和票据仍被拒绝', async (): Promise<void> => {
    const tx = { $queryRaw: jest.fn().mockResolvedValue([]), document: { findFirst: jest.fn().mockResolvedValue(null) },
      documentUpload: { findFirst: jest.fn().mockResolvedValue(null) } } as unknown as Prisma.TransactionClient;
    await expect(activeDocument(tx, randomUUID(), randomUUID())).rejects.toMatchObject({ status: 403 });
    await expect(uploadTicket(tx, randomUUID(), randomUUID(), randomUUID())).rejects.toMatchObject({ status: 403 });
  });
  it('归集入口验证渠道、归属和活跃匹配状态；不接受手工来源混入归集 ID', async (): Promise<void> => {
    const find = jest.fn().mockResolvedValue(null);
    const tx = { ingestionRecord: { findFirst: find } } as unknown as Prisma.TransactionClient;
    const userId = randomUUID(); const caseId = randomUUID(); const id = randomUUID();
    await expect(validateOrigin(tx, userId, caseId, 'MANUAL', id)).rejects.toMatchObject({ status: 403 });
    await expect(validateOrigin(tx, userId, caseId, 'SMS', null)).rejects.toMatchObject({ status: 403 });
    await expect(validateOrigin(tx, userId, caseId, 'SMS', id)).rejects.toMatchObject({ status: 403 });
    find.mockResolvedValue({ id });
    await expect(validateOrigin(tx, userId, caseId, 'SMS', id)).resolves.toBeUndefined();
    expect(find).toHaveBeenLastCalledWith({ where: { id, userId, matchedCaseId: caseId, channel: 'SMS',
      deletedAt: null, status: { in: ['MATCHED', 'ASSIGNED'] } } });
  });
});

describe('文件服务单元：过期对象回收', (): void => {
  const expired = { id: randomUUID(), caseId: randomUUID(), documentId: randomUUID(), pendingKey: 'pending', storageKey: 'final',
    expiresAt: new Date(0), cleanedAt: null };
  const remove = jest.fn().mockResolvedValue(undefined);
  const update = jest.fn().mockResolvedValue({});
  const find = jest.fn().mockResolvedValue(expired);
  const document = jest.fn().mockResolvedValue({ id: expired.documentId });
  const many = jest.fn().mockResolvedValue([expired]);
  const tx = { $queryRaw: jest.fn().mockResolvedValue([]), documentUpload: { findUniqueOrThrow: find, update },
    document: { findUnique: document }, auditLog: { create: jest.fn().mockResolvedValue({}) } };
  const repository = { db: { documentUpload: { findMany: many },
    $transaction: async (fn: (value: unknown) => Promise<unknown>): Promise<unknown> => fn(tx) } } as unknown as PrismaRepository;
  const storage = { delete: remove } as unknown as StorageService;
  beforeEach((): void => { jest.clearAllMocks(); find.mockResolvedValue(expired); many.mockResolvedValue([expired]); });

  it('已登记对象（含软删除）永久避开自动清理，只删临时对象；并发 sweep 合并同一批次', async (): Promise<void> => {
    const service = new DocumentCleanupService(repository, storage);
    const first = service.sweep(); const second = service.sweep();
    expect(first).toBe(second);
    expect(await first).toEqual({ cleaned: 1, failed: 0 });
    expect(remove).toHaveBeenCalledTimes(1); expect(remove).toHaveBeenCalledWith('pending');
    expect(update).toHaveBeenCalledTimes(1);
    await service.onModuleDestroy();
  });
  it('已被其他实例清理或尚未到安全窗口的票据不删除对象', async (): Promise<void> => {
    const service = new DocumentCleanupService(repository, storage);
    find.mockResolvedValueOnce({ ...expired, cleanedAt: new Date() });
    expect(await service.sweep()).toEqual({ cleaned: 0, failed: 0 });
    find.mockResolvedValueOnce({ ...expired, expiresAt: new Date() });
    expect(await service.sweep()).toEqual({ cleaned: 0, failed: 0 });
    expect(remove).not.toHaveBeenCalled();
  });
  it('数据库暂时不可用转为失败计数，下一批可重试；启动和停止不会遗留定时器', async (): Promise<void> => {
    jest.useFakeTimers();
    try {
      const service = new DocumentCleanupService(repository, storage);
      many.mockRejectedValueOnce(new Error('fictional-private-database-detail'));
      expect(await service.sweep()).toEqual({ cleaned: 0, failed: 1 });
      service.onModuleInit();
      await jest.advanceTimersByTimeAsync(60000);
      await service.onModuleDestroy();
      expect(jest.getTimerCount()).toBe(0);
      expect(many).toHaveBeenCalledTimes(2);
    } finally { jest.useRealTimers(); }
  });
});
