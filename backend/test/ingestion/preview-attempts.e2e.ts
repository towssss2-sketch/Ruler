import { randomUUID, createHash } from 'node:crypto';
import { Account, app, baseUrl, login, register, repository, request } from '../auth/fixture';
import { installDocumentFixture, storage, uploadInput } from '../document/fixture';
import { storageFetch } from '../storage/minio-fixture';
import { complete } from './file-fixture';
import { fictionalPdf } from './text-fixtures';
import { PreviewAttemptService } from '../../src/modules/ingestion/extraction/preview-attempt.service';
import { PrismaRepository } from '../../src/prisma.repository';

installDocumentFixture();
let owner: Account; let access: string; let id: string;
beforeEach(async (): Promise<void> => {
  owner = await register(); access = (await login(owner)).accessToken;
  const bytes = fictionalPdf();
  const offer = await request('/ingestion/files/presign', uploadInput({ fileName: '虚构记录.pdf',
    mimeType: 'application/pdf', sizeBytes: bytes.length, contentMd5: createHash('md5').update(bytes).digest('base64') }), access);
  expect(offer.status).toBe(201);
  const put = await storageFetch(offer.data.url as string, { method: 'PUT', headers: offer.data.headers as Record<string, string>, body: Uint8Array.from(bytes) });
  expect(put.status).toBe(200); await put.arrayBuffer();
  const received = await complete(access, offer.data.uploadId as string); expect(received.status).toBe(201);
  id = received.data.id as string;
});
afterEach((): void => { jest.restoreAllMocks(); });
const history = (suffix = '', token = access, record = id): ReturnType<typeof request> => request(`/ingestion/${record}/preview-attempts${suffix}`, undefined, token);
const preview = (): ReturnType<typeof request> => request(`/ingestion/${id}/preview`, {}, access);

async function abandoned(): Promise<string> {
  const row = await repository.db.ingestionPreviewAttempt.create({ data: { userId: owner.id, ingestionId: id,
    startedAt: new Date(Date.now() - 180000), leaseExpiresAt: new Date(Date.now() - 60000) } });
  return row.id;
}

describe('提取记录持久化与中断恢复', (): void => {
  it('空记录查询不启动提取；实际成功与失败历史重登保留，仅返回安全元数据且不缓存', async (): Promise<void> => {
    expect((await history()).data).toEqual({ items: [], total: 0, page: 1, pageSize: 20 });
    const fail = jest.spyOn(storage(), 'read').mockRejectedValueOnce(new Error('fictional-private-error'));
    const failed = await preview(); fail.mockRestore(); expect(failed.status).toBe(201);
    const succeeded = await preview(); expect(succeeded.status).toBe(201);
    access = (await login(owner)).accessToken;
    const response = await fetch(`${baseUrl}/ingestion/${id}/preview-attempts`, { headers: { authorization: `Bearer ${access}` } });
    expect(response.status).toBe(200); expect(response.headers.get('cache-control')).toBe('private, no-store');
    const result = await history(); expect(result.data.total).toBe(2);
    const rows = result.data.items as Array<Record<string, unknown>>;
    expect(rows.map((row) => row.status)).toEqual(['SUCCEEDED', 'MANUAL_REQUIRED']);
    expect(rows[1]).toMatchObject({ id: failed.data.attemptId, reason: 'UNAVAILABLE', retryable: true });
    expect(Object.keys(rows[0]!).sort()).toEqual(['finishedAt', 'id', 'reason', 'retryable', 'startedAt', 'status']);
    for (const text of ['fictional-private-error', 'Fictional test document', 'storageKey', 'userId', 'leaseExpiresAt']) expect(result.raw.includes(text)).toBe(false);
    expect(await repository.db.ingestionPreviewAttempt.count({ where: { ingestionId: id } })).toBe(2);
    expect((await request(`/ingestion/${id}`, undefined, access)).data.status).toBe('PENDING_MATCH');
  });
  it('未知、他人、删除、纯文字、未登录及非法页码拒绝，不读取或修改尝试', async (): Promise<void> => {
    await preview(); const other = (await login(await register())).accessToken;
    expect((await request(`/ingestion/${id}/preview-attempts`)).status).toBe(401);
    expect((await history('', other)).status).toBe(403);
    expect((await history('', access, randomUUID())).status).toBe(403);
    expect((await history('', access, 'bad')).status).toBe(400);
    for (const query of ['?page=0', '?page=10000', '?page=1&page=2', '?pageSize=101', '?userId=x', '?__proto__=x']) {
      expect((await history(query)).status).toBe(400);
    }
    const text = await request('/ingestion/wechat', { rawContent: '虚构文字没有附件' }, access);
    expect((await history('', access, text.data.id as string)).status).toBe(403);
    await repository.db.ingestionRecord.update({ where: { id }, data: { deletedAt: new Date() } });
    expect((await history()).status).toBe(403);
    expect(await repository.db.ingestionPreviewAttempt.count({ where: { ingestionId: id } })).toBe(1);
  });
  it('同时间记录按 UUID 倒序稳定分页；越界空页与忽略后的历史保留', async (): Promise<void> => {
    const now = new Date(); const ids = [randomUUID(), randomUUID(), randomUUID()].sort().reverse();
    await repository.db.ingestionPreviewAttempt.createMany({ data: ids.map((attemptId) => ({ id: attemptId, userId: owner.id,
      ingestionId: id, status: 'SUCCEEDED', startedAt: now, finishedAt: now, leaseExpiresAt: new Date(now.getTime() + 120000) })) });
    await request(`/ingestion/${id}/ignore`, {}, access);
    for (let page = 1; page <= 3; page++) {
      const result = await history(`?page=${page}&pageSize=1`);
      expect(result.data).toMatchObject({ total: 3, page, pageSize: 1, items: [{ id: ids[page - 1], status: 'SUCCEEDED', retryable: false }] });
    }
    expect((await history('?page=4&pageSize=1')).data.items).toEqual([]);
  });
  it('独立服务实例共用数据库槽位；读取处理中状态不触发第二次解析，完成后可再次申请', async (): Promise<void> => {
    const first = app.get(PreviewAttemptService), second = new PreviewAttemptService(repository);
    const attempt = await first.begin(owner.id, id);
    expect((await history()).data.items).toMatchObject([{ status: 'RUNNING', retryable: false, finishedAt: null }]);
    await expect(second.begin(owner.id, id)).rejects.toMatchObject({ status: 429 });
    expect((await preview()).status).toBe(429);
    await first.finish(owner.id, id, attempt.attemptId, { state: 'MANUAL_REQUIRED', reason: 'NO_TEXT', retryable: false });
    expect((await history()).data.items).toMatchObject([{ status: 'MANUAL_REQUIRED', retryable: false, reason: 'NO_TEXT' }]);
    expect((await preview()).status).toBe(201);
  });
  it('新连接可读取遗留中断；GET 不写库，新尝试固化旧中断并且迟到完成被拒绝', async (): Promise<void> => {
    const oldId = await abandoned();
    const freshRepository = new PrismaRepository();
    try {
      const fresh = new PreviewAttemptService(freshRepository);
      const result = await fresh.history(owner.id, id, { page: '1', pageSize: '20' });
      expect(result.items[0]).toMatchObject({ id: oldId, status: 'INTERRUPTED', retryable: true });
      expect((await repository.db.ingestionPreviewAttempt.findUniqueOrThrow({ where: { id: oldId } })).status).toBe('RUNNING');
      const newer = await fresh.begin(owner.id, id);
      await expect(fresh.finish(owner.id, id, oldId, { state: 'TEXT', text: '迟到虚构正文' })).rejects.toMatchObject({ status: 409 });
      expect((await repository.db.ingestionPreviewAttempt.findUniqueOrThrow({ where: { id: newer.attemptId } })).status).toBe('RUNNING');
      await fresh.finish(owner.id, id, newer.attemptId, { state: 'TEXT', text: '新虚构正文' });
      const items = (await history()).data.items as Array<Record<string, unknown>>;
      expect(items.map((row) => row.status)).toEqual(['SUCCEEDED', 'INTERRUPTED']);
      expect(await repository.db.auditLog.count({ where: { resourceId: id, action: 'INGESTION_PREVIEW_INTERRUPTED' } })).toBe(1);
    } finally { await freshRepository.onModuleDestroy(); }
  });
  it('过期完成原子记为中断而非成功；不存在的尝试和重复完成拒绝', async (): Promise<void> => {
    const attempts = app.get(PreviewAttemptService), old = await abandoned();
    await expect(attempts.finish(owner.id, id, old, { state: 'TEXT', text: '不能返回的虚构正文' })).rejects.toMatchObject({ status: 409 });
    const saved = await repository.db.ingestionPreviewAttempt.findUniqueOrThrow({ where: { id: old } });
    expect(saved.status).toBe('INTERRUPTED'); expect(saved.finishedAt).toEqual(saved.leaseExpiresAt);
    await expect(attempts.finish(owner.id, id, randomUUID(), { state: 'TEXT', text: 'x' })).rejects.toMatchObject({ status: 403 });
    const result = await preview();
    await expect(attempts.finish(owner.id, id, result.data.attemptId as string, { state: 'TEXT', text: 'x' })).rejects.toMatchObject({ status: 409 });
  });
  it('结束事务故障不丢开始记录，不把正文当成功返回，重试须等租期释放', async (): Promise<void> => {
    const attempts = app.get(PreviewAttemptService);
    const finish = jest.spyOn(attempts, 'finish').mockRejectedValueOnce(new Error('fictional-private-commit'));
    const result = await preview(); finish.mockRestore();
    expect(result.status).toBe(500); expect(result.raw.includes('Fictional test document')).toBe(false);
    expect(result.raw.includes('fictional-private-commit')).toBe(false);
    expect((await history()).data.items).toMatchObject([{ status: 'RUNNING', retryable: false }]);
    expect((await preview()).status).toBe(429);
  });
  it('账号停用与处理期间删除仍拒绝结束和历史，原先的开始记录保留', async (): Promise<void> => {
    const attempts = app.get(PreviewAttemptService), started = await attempts.begin(owner.id, id);
    await repository.db.user.update({ where: { id: owner.id }, data: { deletedAt: new Date() } });
    await expect(attempts.begin(owner.id, id)).rejects.toMatchObject({ status: 403 });
    await expect(attempts.history(owner.id, id, { page: '1', pageSize: '20' })).rejects.toMatchObject({ status: 403 });
    await expect(attempts.finish(owner.id, id, started.attemptId, { state: 'TEXT', text: 'x' })).rejects.toMatchObject({ status: 403 });
    expect((await repository.db.ingestionPreviewAttempt.findUniqueOrThrow({ where: { id: started.attemptId } })).status).toBe('RUNNING');
  });
});
