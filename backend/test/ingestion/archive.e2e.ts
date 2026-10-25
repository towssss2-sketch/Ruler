import { randomUUID } from 'node:crypto';
import { Account, app, login, register, repository, request } from '../auth/fixture';
import { content, installDocumentFixture, storage, uploadInput } from '../document/fixture';
import { newCase } from '../case/fixture';
import { complete, fileOffer } from './file-fixture';
import { AssignInput } from '../../src/modules/ingestion/ingestion-assign-policy';
import { AssignmentPreparation, IngestionAssignTicketService } from '../../src/modules/ingestion/ingestion-assign-ticket.service';
import * as policy from '../../src/modules/document/document-policy';
import { storageFetch } from '../storage/minio-fixture';

installDocumentFixture();
let account: Account; let access: string; let caseId: string; let id: string; let documentId: string;
beforeEach(async (): Promise<void> => {
  account = await register(); access = (await login(account)).accessToken; caseId = await newCase(access);
  id = (await complete(access, (await fileOffer(access)).uploadId)).data.id as string;
  const result = await request(`/ingestion/${id}/assign`, { caseId, category: 'SERVICE_CONTRACT' }, access);
  expect(result.status).toBe(201); documentId = result.data.id as string;
});
afterEach((): void => { jest.restoreAllMocks(); });
function withdraw(): ReturnType<typeof request> {
  return request(`/ingestion/${id}/withdraw`, { caseId, documentId }, access);
}
function locate(): ReturnType<typeof request> { return request(`/ingestion/${id}/assignment`, undefined, access); }

describe('归档去向与显式撤回', (): void => {
  it('当前案件分类摘要最小化；撤回移出案件、保留原件/配额，重登待定可读', async (): Promise<void> => {
    const view = await locate(); expect(view.status).toBe(200);
    expect(view.data).toMatchObject({ state: 'AVAILABLE', caseId, documentId, category: 'SERVICE_CONTRACT', canWithdraw: true });
    expect(Object.keys(view.data).sort()).toEqual(['canWithdraw','caseId','caseNo','category','court','documentId','state']);
    const doc = await repository.db.document.findUniqueOrThrow({ where: { id: documentId } });
    expect((await withdraw()).data).toEqual({ withdrawn: true, status: 'PENDING_MATCH' });
    access = (await login(account)).accessToken;
    expect((await locate()).data).toEqual({ state: 'UNASSIGNED' });
    expect((await request(`/cases/${caseId}/documents`, undefined, access)).data.total).toBe(0);
    const item = await request(`/ingestion/${id}`, undefined, access);
    expect(item.data).toMatchObject({ status: 'PENDING_MATCH', assignmentRevision: 1 });
    expect((await request(`/documents/${documentId}/download`, undefined, access)).status).toBe(403);
    expect(await storage().exists(doc.storageKey)).toBe(true);
    const signed = await request(`/ingestion/${id}/file/download`, undefined, access);
    const download = await storageFetch(signed.data.url as string);
    expect(Buffer.from(await download.arrayBuffer()).equals(content)).toBe(true);
    expect((await repository.db.user.findUniqueOrThrow({ where: { id: account.id } })).storageUsedBytes).toBe(BigInt(content.length * 2));
  });
  it('并发撤回幂等，忽略后迟到重试不恢复；重新归档后旧文档和旧版本请求均拒绝', async (): Promise<void> => {
    expect((await Promise.all([withdraw(), withdraw()])).map((r): number => r.status)).toEqual([201,201]);
    expect(await repository.db.auditLog.count({ where: { resourceId: documentId, action: 'INGESTION_FILE_WITHDRAWN' } })).toBe(1);
    const nextCase = await newCase(access);
    const path = `/ingestion/${id}/assign`;
    expect((await request(path, { caseId: nextCase, category: 'COURT_DOCUMENT' }, access)).status).toBe(409);
    const next = await request(path, { caseId: nextCase, category: 'COURT_DOCUMENT', revision: 1 }, access);
    expect(next.status).toBe(201); expect(next.data.id).not.toBe(documentId);
    expect((await withdraw()).status).toBe(409);
    expect((await locate()).data).toMatchObject({ caseId: nextCase, documentId: next.data.id, category: 'COURT_DOCUMENT' });
    caseId = nextCase; documentId = next.data.id as string; expect((await withdraw()).status).toBe(201);
    await request(`/ingestion/${id}/ignore`, {}, access);
    expect((await withdraw()).data.status).toBe('IGNORED');
    expect((await request(`/ingestion/${id}`, undefined, access)).data.assignmentRevision).toBe(2);
  });
  it('鉴权、双资源归属、伪造文档及未知字段受限，删除案件不泄露历史摘要', async (): Promise<void> => {
    const other = (await login(await register())).accessToken; const otherCase = await newCase(other);
    const body = { caseId, documentId };
    expect((await request(`/ingestion/${id}/assignment`)).status).toBe(401);
    expect((await request(`/ingestion/${id}/assignment`, undefined, other)).status).toBe(403);
    expect((await request(`/ingestion/${id}/withdraw`, body)).status).toBe(401);
    expect((await request(`/ingestion/${id}/withdraw`, { ...body, caseId: otherCase }, other)).status).toBe(403);
    expect((await request(`/ingestion/${id}/withdraw`, { ...body, caseId: otherCase }, access)).status).toBe(403);
    expect((await request(`/ingestion/${id}/withdraw`, { ...body, documentId: randomUUID() }, access)).status).toBe(403);
    for (const extra of [{ documentId: 'bad' }, { category: 'OTHER' }, { userId: account.id }]) {
      expect((await request(`/ingestion/${id}/withdraw`, { ...body, ...extra }, access)).status).toBe(400);
    }
    for (const revision of [-1, 1.5, '1', 2147483648, null]) {
      expect((await request(`/ingestion/${id}/assign`, { caseId, category: 'OTHER', revision }, access)).status).toBe(400);
    }
    await request(`/cases/${caseId}`, undefined, access, 'DELETE');
    expect((await locate()).status).toBe(403); expect((await withdraw()).status).toBe(403);
  });
  it('审计失败撤回整体回滚，原归档状态和下载仍可用', async (): Promise<void> => {
    const spy = jest.spyOn(policy,'auditDocument').mockRejectedValueOnce(new Error('fictional-private-error'));
    const result = await withdraw(); spy.mockRestore();
    expect(result.status).toBe(500); expect(result.raw.includes('fictional-private-error')).toBe(false);
    expect((await locate()).data.canWithdraw).toBe(true);
    expect((await request(`/documents/${documentId}/download`, undefined, access)).status).toBe(200);
    expect((await request(`/ingestion/${id}`, undefined, access)).data.assignmentRevision).toBe(0);
    expect((await withdraw()).status).toBe(201);
  });
  it('已有后续版本阻止撤回；仅有未完成新版本票据则撤回后禁止其登记', async (): Promise<void> => {
    const offer = await request(`/cases/${caseId}/documents/presign`, uploadInput({ previousDocumentId: documentId }), access);
    expect(offer.status).toBe(201);
    const put = await storageFetch(offer.data.url as string, { method:'PUT', headers: offer.data.headers as Record<string,string>, body: Uint8Array.from(content) });
    expect(put.status).toBe(200); await put.arrayBuffer();
    const second = await request(`/cases/${caseId}/documents`, { uploadId: offer.data.uploadId, category:'SERVICE_CONTRACT' }, access);
    expect(second.status).toBe(201); expect((await locate()).data.canWithdraw).toBe(false);
    expect((await withdraw()).status).toBe(409);
    await request(`/documents/${second.data.id}`, undefined, access, 'DELETE');
    const pending = await request(`/cases/${caseId}/documents/presign`, uploadInput({ previousDocumentId: documentId }), access);
    expect((await withdraw()).status).toBe(201);
    expect((await request(`/cases/${caseId}/documents`, { uploadId:pending.data.uploadId, category:'SERVICE_CONTRACT' },access)).status).toBe(409);
  });
  it('两阶段之间已撤回时迟到的原归档请求不能重新生成文件', async (): Promise<void> => {
    await withdraw();
    const tickets = app.get(IngestionAssignTicketService); const prepare = tickets.prepare.bind(tickets);
    const spy = jest.spyOn(tickets, 'prepare').mockImplementationOnce(async (user: string, record: string, input: AssignInput): Promise<AssignmentPreparation> => {
      const prepared = await prepare(user, record, input);
      // 模拟另一请求完成相同归档后撤回，再让原请求进入第二事务。
      const saved = await request(`/ingestion/${id}/assign`, { caseId, category:'SERVICE_CONTRACT', revision:1 }, access);
      expect(saved.status).toBe(201); documentId = saved.data.id as string;
      expect((await withdraw()).status).toBe(201); return prepared;
    });
    const late = await request(`/ingestion/${id}/assign`, { caseId, category:'SERVICE_CONTRACT', revision:1 },access);
    spy.mockRestore(); expect(late.status).toBe(409);
    expect((await request(`/ingestion/${id}`, undefined,access)).data).toMatchObject({ status:'PENDING_MATCH', assignmentRevision:2 });
    expect(await repository.db.document.count({ where: { ingestionId:id, deletedAt:null } })).toBe(0);
  });
  it('普通删除不算撤回、文字不能撤回，归集停用后不可查询去向', async (): Promise<void> => {
    await request(`/documents/${documentId}`, undefined, access, 'DELETE');
    expect((await locate()).data).toEqual({ state:'UNAVAILABLE' }); expect((await withdraw()).status).toBe(409);
    const text = await request('/ingestion/wechat',{rawContent:'虚构纯文字'},access);
    expect((await request(`/ingestion/${text.data.id}/withdraw`, {caseId,documentId},access)).status).toBe(403);
    await repository.db.ingestionRecord.update({ where:{id}, data:{deletedAt:new Date()} });
    expect((await locate()).status).toBe(403);
  });
});
