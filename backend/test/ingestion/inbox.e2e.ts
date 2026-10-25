import { randomUUID } from 'node:crypto';
import { Account, app, installFixture, login, register, repository, request } from '../auth/fixture';
import { newCase } from '../case/fixture';
import { IngestionService } from '../../src/modules/ingestion/ingestion.service';

installFixture();
let account: Account; let access: string;
beforeEach(async (): Promise<void> => {
  account = await register(); access = (await login(account)).accessToken;
});

/** 只通过真实接收接口生成待定记录，原文全部虚构。 */
async function receive(text = '虚构转发材料'): Promise<string> {
  const response = await request('/ingestion/wechat', { rawContent: text }, access);
  expect(response.status).toBe(201); return response.data.id as string;
}

describe('文字待定区真实 HTTP 与数据库', (): void => {
  it('接收、摘要、详情、忽略与历史闭环；加密、审计及输出字段最小化', async (): Promise<void> => {
    const text = 'fictional-private-text\n' + '虚构'.repeat(200);
    const id = await receive(text);
    const record = await repository.db.ingestionRecord.findUniqueOrThrow({ where: { id } });
    expect(Buffer.from(record.rawContent).includes(Buffer.from('fictional-private-text'))).toBe(false);
    expect(record).toMatchObject({ stage: 'RECEIVE', status: 'PENDING_MATCH', matchedCaseId: null, aiResult: null,
      attachmentKeys: [], deliveryLink: null, attemptCount: 0, nextRetryAt: null });
    const pending = await request('/ingestion/pending', undefined, access);
    expect(pending.data).toMatchObject({ total: 1, page: 1, pageSize: 20 });
    const items = pending.data.items as Record<string, unknown>[];
    expect(Object.keys(items[0]!).sort()).toEqual(['assignmentRevision', 'channel', 'file', 'id', 'preview', 'receivedAt', 'status']);
    expect(Array.from(items[0]!.preview as string)).toHaveLength(200);
    expect((await request(`/ingestion/${id}`, undefined, access)).data.rawContent).toBe(text);
    expect((await request(`/ingestion/${id}/ignore`, {}, access)).status).toBe(201);
    expect((await request(`/ingestion/${id}/ignore`, {}, access)).data.ignored).toBe(true);
    expect((await request('/ingestion/pending', undefined, access)).data.total).toBe(0);
    const logs = await request('/ingestion/logs', undefined, access);
    expect(logs.data.total).toBe(1); expect((logs.data.items as Record<string, unknown>[])[0]!.status).toBe('IGNORED');
    expect((await request(`/ingestion/${id}`, undefined, access)).data.rawContent).toBe(text);
    const audits = await repository.db.auditLog.findMany({ where: { resourceId: id } });
    expect(audits.map((a): string => a.action).sort()).toEqual(['INGESTION_IGNORED', 'INGESTION_RECEIVED']);
    expect(audits.every((a): boolean => JSON.stringify(a.detail) === '{}')).toBe(true);
    expect(JSON.stringify(audits).includes('fictional-private-text')).toBe(false);
  });
  it('并发接收只写一次；归一化重试保持原状态和日期；同文不同账号各自独立', async (): Promise<void> => {
    const replies = await Promise.all(Array.from({ length: 5 }, (): ReturnType<typeof request> =>
      request('/ingestion/wechat', { rawContent: ' 虚构\r\n重复 ' }, access)));
    expect(replies.every((r): boolean => r.status === 201)).toBe(true);
    expect(replies.filter((r): boolean => r.data.duplicate === false)).toHaveLength(1);
    expect(new Set(replies.map((r): unknown => r.data.id)).size).toBe(1);
    const id = replies[0]!.data.id as string;
    const before = await repository.db.ingestionRecord.findUniqueOrThrow({ where: { id } });
    await request(`/ingestion/${id}/ignore`, {}, access);
    const retry = await request('/ingestion/wechat', { rawContent: '虚构\n重复' }, access);
    expect(retry.data).toEqual({ id, status: 'IGNORED', duplicate: true });
    const after = await repository.db.ingestionRecord.findUniqueOrThrow({ where: { id } });
    expect(after.receivedAt).toEqual(before.receivedAt);
    const other = await register(); const otherAccess = (await login(other)).accessToken;
    const independent = await request('/ingestion/wechat', { rawContent: '虚构\n重复' }, otherAccess);
    expect(independent.data.id).not.toBe(id); expect(independent.data.duplicate).toBe(false);
    const second = await repository.db.ingestionRecord.findUniqueOrThrow({ where: { id: independent.data.id as string } });
    expect(second.contentHash).not.toBe(before.contentHash);
  });
  it('真实身份隔离、伪造归属拒绝、已删除和不存在统一拒绝', async (): Promise<void> => {
    const id = await receive(); const other = await register(); const token = (await login(other)).accessToken;
    for (const path of ['/ingestion/pending', '/ingestion/logs', `/ingestion/${id}`]) {
      expect((await request(path)).status).toBe(401);
    }
    expect((await request('/ingestion/wechat', { rawContent: '虚构' })).status).toBe(401);
    expect((await request(`/ingestion/${id}/ignore`, {})).status).toBe(401);
    expect((await request('/ingestion/pending', undefined, token)).data.total).toBe(0);
    expect((await request('/ingestion/logs', undefined, token)).data.total).toBe(0);
    for (const target of [id, randomUUID()]) {
      expect((await request(`/ingestion/${target}`, undefined, token)).status).toBe(403);
      expect((await request(`/ingestion/${target}/ignore`, {}, token)).status).toBe(403);
    }
    expect((await request('/ingestion/pending?userId=' + account.id, undefined, token)).status).toBe(400);
    expect((await request(`/ingestion/${id}/ignore`, { status: 'ASSIGNED' }, access)).status).toBe(400);
    await repository.db.ingestionRecord.update({ where: { id }, data: { deletedAt: new Date() } });
    expect((await request(`/ingestion/${id}`, undefined, access)).status).toBe(403);
    expect((await request(`/ingestion/${id}/ignore`, {}, access)).status).toBe(403);
    expect((await request('/ingestion/logs', undefined, access)).data.total).toBe(0);
    expect((await request('/ingestion/wechat', { rawContent: '虚构转发材料' }, access)).status).toBe(409);
  });
  it('分页稳定不漏项，历史含忽略记录，非法参数与附件拒绝', async (): Promise<void> => {
    for (let i = 0; i < 3; i++) await receive(`虚构分页${i}`);
    const first = await request('/ingestion/pending?pageSize=2', undefined, access);
    const second = await request('/ingestion/pending?page=2&pageSize=2', undefined, access);
    const items = [...first.data.items as Record<string, unknown>[], ...second.data.items as Record<string, unknown>[]];
    expect(first.data.total).toBe(3); expect(items).toHaveLength(3);
    expect(new Set(items.map((r): unknown => r.id)).size).toBe(3);
    expect((await request('/ingestion/pending?page=3&pageSize=2', undefined, access)).data.items).toEqual([]);
    for (const path of ['/ingestion/pending?page=0', '/ingestion/logs?pageSize=101', '/ingestion/not-a-uuid']) {
      expect((await request(path, undefined, access)).status).toBe(400);
    }
    for (const body of [{ rawContent: ' ' }, { rawContent: '虚构', attachmentKeys: ['fake'] },
      { rawContent: '虚构', channel: 'SMS' }, { rawContent: '虚构', aiResult: {} }]) {
      expect((await request('/ingestion/wechat', body, access)).status).toBe(400);
    }
    expect((await request('/ingestion/logs', undefined, access)).data.total).toBe(3);
  });
  it('已匹配/已指派不允许忽略；并发忽略一次审计', async (): Promise<void> => {
    const id = await receive(); const caseId = await newCase(access);
    for (const status of ['MATCHED', 'ASSIGNED'] as const) {
      await repository.db.ingestionRecord.update({ where: { id }, data: { matchedCaseId: caseId, status } });
      expect((await request(`/ingestion/${id}/ignore`, {}, access)).status).toBe(409);
      expect((await request('/ingestion/pending', undefined, access)).data.total).toBe(0);
    }
    const pendingId = await receive('虚构并发忽略');
    const replies = await Promise.all([1, 2, 3].map((): ReturnType<typeof request> =>
      request(`/ingestion/${pendingId}/ignore`, {}, access)));
    expect(replies.every((r): boolean => r.status === 201)).toBe(true);
    expect(await repository.db.auditLog.count({ where: { resourceId: pendingId, action: 'INGESTION_IGNORED' } })).toBe(1);
  });
  it('审计失败整体回滚，原文仍能重试；停用账号无法通过服务写入', async (): Promise<void> => {
    const service = app.get(IngestionService);
    const spy = jest.spyOn(service as unknown as { audit: () => Promise<void> }, 'audit')
      .mockRejectedValueOnce(new Error('fictional-audit-failure'));
    const failed = await request('/ingestion/wechat', { rawContent: '虚构回滚' }, access);
    spy.mockRestore(); expect(failed.status).toBe(500); expect(failed.raw.includes('fictional-audit-failure')).toBe(false);
    expect((await request('/ingestion/pending', undefined, access)).data.total).toBe(0);
    const id = await receive('虚构回滚');
    const ignoreSpy = jest.spyOn(service as unknown as { audit: () => Promise<void> }, 'audit')
      .mockRejectedValueOnce(new Error('fictional-audit-failure'));
    expect((await request(`/ingestion/${id}/ignore`, {}, access)).status).toBe(500);
    ignoreSpy.mockRestore(); expect((await request(`/ingestion/${id}`, undefined, access)).data.status).toBe('PENDING_MATCH');
    await repository.db.user.update({ where: { id: account.id }, data: { deletedAt: new Date() } });
    await expect(service.receive(account.id, '虚构停用')).rejects.toThrow();
    await expect(service.ignore(account.id, id)).rejects.toThrow();
  });
  it('密文损坏不返回部分原文或密钥材料', async (): Promise<void> => {
    const id = await receive('虚构损坏');
    const row = await repository.db.ingestionRecord.findUniqueOrThrow({ where: { id } });
    const bytes = new Uint8Array(row.rawContent); bytes[bytes.length - 1] = bytes[bytes.length - 1]! ^ 1;
    await repository.db.ingestionRecord.update({ where: { id }, data: { rawContent: bytes } });
    for (const path of ['/ingestion/pending', `/ingestion/${id}`]) {
      const response = await request(path, undefined, access);
      expect(response.status).toBe(500); expect(response.raw.includes('虚构损坏')).toBe(false);
      expect(response.raw.includes('解密')).toBe(false);
    }
  });
});
