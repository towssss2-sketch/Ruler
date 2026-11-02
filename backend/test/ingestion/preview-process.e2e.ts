import { setTimeout as delay } from 'node:timers/promises';
import { login, register, repository, request } from '../auth/fixture';
import { installDocumentFixture } from '../document/fixture';
import { complete, fileOffer } from './file-fixture';
import { fictionalPdf } from './text-fixtures';
import { message, PreviewProcess, processRequest, startPreviewProcess, stopPreviewProcess } from './preview-process-fixture';

installDocumentFixture();

/** 等待数据库原两分钟租期真实到期，不改时钟、记录、限流或生产租期。 */
async function waitForExpiry(expiresAt: Date): Promise<void> {
  const rows = await repository.db.$queryRaw<Array<{ now: Date }>>`SELECT clock_timestamp()::timestamptz(3) AS now`;
  const remaining = expiresAt.getTime() - rows[0]!.now.getTime();
  expect(remaining).toBeGreaterThan(0); expect(remaining).toBeLessThanOrEqual(120000);
  await delay(remaining + 100);
}

describe('提取服务真实进程中断恢复', (): void => {
  it('SIGKILL 后新进程读取原记录，租期内拒绝重复提取，实际到期后显式重试成功且不归档', async (): Promise<void> => {
    const servers: PreviewProcess[] = [];
    try {
      const owner = await register(), access = (await login(owner)).accessToken;
      const offer = await fileOffer(access, '虚构进程恢复.pdf', fictionalPdf());
      const received = await complete(access, offer.uploadId); expect(received.status).toBe(201);
      const id = received.data.id as string, path = `/ingestion/${id}`;
      const original = await repository.db.ingestionRecord.findUniqueOrThrow({ where: { id } });
      const first = await startPreviewProcess(true); servers.push(first);
      const pendingRead = message(first.child, 'READ_PENDING');
      const pendingRequest = processRequest(first, `${path}/preview`, access, {}).then(() => 'RESPONSE', () => 'DISCONNECTED');
      await pendingRead;
      const running = await repository.db.ingestionPreviewAttempt.findFirstOrThrow({ where: { ingestionId: id } });
      expect(running.status).toBe('RUNNING');
      expect(running.leaseExpiresAt.getTime() - running.startedAt.getTime()).toBe(120000);
      expect(first.child.kill('SIGKILL')).toBe(true);
      expect(await first.exited).toEqual({ code: null, signal: 'SIGKILL' });
      expect(await pendingRequest).toBe('DISCONNECTED');
      const second = await startPreviewProcess(false); servers.push(second);
      expect(second.child.pid).not.toBe(first.child.pid);
      const history = await processRequest(second, `${path}/preview-attempts`, access);
      expect(history.status).toBe(200);
      expect(history.data).toMatchObject({ total: 1, items: [{ id: running.id, status: 'RUNNING', retryable: false }] });
      expect((await processRequest(second, `${path}/preview`, access, {})).status).toBe(429);
      await waitForExpiry(running.leaseExpiresAt);
      const expired = await processRequest(second, `${path}/preview-attempts`, access);
      expect(expired.data).toMatchObject({ total: 1, items: [{ id: running.id, status: 'INTERRUPTED', retryable: true }] });
      expect((await repository.db.ingestionPreviewAttempt.findUniqueOrThrow({ where: { id: running.id } })).status).toBe('RUNNING');
      const retried = await processRequest(second, `${path}/preview`, access, {});
      expect(retried.status).toBe(201);
      expect(retried.data.extraction).toMatchObject({ state: 'TEXT', text: expect.stringContaining('Fictional test document') });
      expect(retried.data.attemptId).not.toBe(running.id);
      const final = await processRequest(second, `${path}/preview-attempts`, access);
      expect(final.data).toMatchObject({ total: 2, items: [{ id: retried.data.attemptId, status: 'SUCCEEDED' },
        { id: running.id, status: 'INTERRUPTED', finishedAt: running.leaseExpiresAt.toISOString() }] });
      expect(await repository.db.auditLog.count({ where: { resourceId: id, action: 'INGESTION_PREVIEW_STARTED' } })).toBe(2);
      expect(await repository.db.auditLog.count({ where: { resourceId: id, action: 'INGESTION_PREVIEW_INTERRUPTED' } })).toBe(1);
      expect(await repository.db.auditLog.count({ where: { resourceId: id, action: 'INGESTION_PREVIEW_FINISHED' } })).toBe(1);
      expect(await repository.db.ingestionRecord.findUniqueOrThrow({ where: { id } })).toEqual(original);
      expect(await repository.db.document.count({ where: { ingestionId: id } })).toBe(0);
      expect((await request(`${path}/preview-attempts`, undefined, (await login(await register())).accessToken)).status).toBe(403);
    } finally { for (const server of servers.reverse()) await stopPreviewProcess(server); }
  }, 180000);
});
