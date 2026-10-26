import { createHash, randomUUID } from 'node:crypto';
import { Account, app, baseUrl, login, register, repository, request } from '../auth/fixture';
import { installDocumentFixture, storage, uploadInput } from '../document/fixture';
import { storageFetch } from '../storage/minio-fixture';
import { complete } from './file-fixture';
import { fictionalDocx, fictionalPdf } from './text-fixtures';
import { DOCX_MIME, ExtractionResult } from '../../src/modules/ingestion/extraction/extraction-result';
import { DocumentTextExtractor } from '../../src/modules/ingestion/extraction/document-text-extractor';

installDocumentFixture();
let account: Account; let access: string; let id: string;
beforeEach(async (): Promise<void> => {
  account = await register(); access = (await login(account)).accessToken;
  id = await receiveFile(access,fictionalPdf(),'application/pdf');
});
afterEach((): void => { jest.restoreAllMocks(); });

async function receiveFile(token: string, bytes: Buffer, mimeType: string): Promise<string> {
  const extension = mimeType === DOCX_MIME ? 'docx' : mimeType === 'application/pdf' ? 'pdf' : 'png';
  const offer = await request('/ingestion/files/presign',uploadInput({fileName:`虚构测试材料.${extension}`,mimeType,sizeBytes:bytes.length,
    contentMd5:createHash('md5').update(bytes).digest('base64')}),token);
  expect(offer.status).toBe(201);
  const put = await storageFetch(offer.data.url as string,{method:'PUT',headers:offer.data.headers as Record<string,string>,body:Uint8Array.from(bytes)});
  expect(put.status).toBe(200); await put.arrayBuffer();
  const received = await complete(token,offer.data.uploadId as string); expect(received.status).toBe(201);
  return received.data.id as string;
}
function preview(token = access, record = id): ReturnType<typeof request> { return request(`/ingestion/${record}/preview`,{},token); }

describe('正文预览真实 HTTP、数据库与 MinIO', (): void => {
  it('真实 PDF 返回正文；重试有独立审计，原件、密文、配额与归档状态不变', async (): Promise<void> => {
    const before = await repository.db.ingestionRecord.findUniqueOrThrow({where:{id},include:{file:true}});
    const quota = (await repository.db.user.findUniqueOrThrow({where:{id:account.id}})).storageUsedBytes;
    const result = await preview(); expect(result.status).toBe(201);
    expect(result.data.extraction).toEqual({state:'TEXT',text:'Fictional test document'});
    expect(result.data.suggestion).toMatchObject({category:null,reason:'NO_TITLE',requiresConfirmation:true});
    expect(Object.keys(result.data).sort()).toEqual(['attemptId','extraction','suggestion']);
    const retry = await preview(); expect(retry.data.attemptId).not.toBe(result.data.attemptId);
    const after = await repository.db.ingestionRecord.findUniqueOrThrow({where:{id}});
    expect(Buffer.from(after.rawContent).equals(Buffer.from(before.rawContent))).toBe(true);
    expect(after).toMatchObject({status:'PENDING_MATCH',stage:'RECEIVE',matchedCaseId:null,assignmentRevision:0,aiResult:null});
    expect((await repository.db.user.findUniqueOrThrow({where:{id:account.id}})).storageUsedBytes).toBe(quota);
    expect(await repository.db.document.count({where:{ingestionId:id}})).toBe(0);
    const logs = await repository.db.auditLog.findMany({where:{resourceId:id,action:{startsWith:'INGESTION_PREVIEW_'}}});
    expect(logs).toHaveLength(4);
    const details = JSON.stringify(logs.map((log): unknown => log.detail));
    expect(details.includes('Fictional test document')).toBe(false); expect(details.includes(before.file!.storageKey)).toBe(false);
    const download = await request(`/ingestion/${id}/file/download`,undefined,access);
    const bytes = await storageFetch(download.data.url as string);
    expect(Buffer.from(await bytes.arrayBuffer()).equals(fictionalPdf())).toBe(true);
  });
  it('真实 DOCX 识别服务合同/案号候选，响应禁止缓存，不生成任务或自动归档', async (): Promise<void> => {
    id = await receiveFile(access,fictionalDocx('法律服务合同\n（2026）浙0302民初123号\n虚构委托正文'),DOCX_MIME);
    const response = await fetch(`${baseUrl}/ingestion/${id}/preview`,{method:'POST',headers:{'content-type':'application/json',authorization:`Bearer ${access}`},body:'{}'});
    expect(response.status).toBe(201); expect(response.headers.get('cache-control')).toBe('private, no-store');
    const result = await response.json() as {data:Record<string,unknown>};
    expect(result.data.suggestion).toMatchObject({category:'SERVICE_CONTRACT',caseNumbers:['(2026)浙0302民初123号'],requiresConfirmation:true});
    expect((result.data.extraction as {text:string}).text).toContain('虚构委托正文');
    expect((await request(`/ingestion/${id}`,undefined,access)).data.status).toBe('PENDING_MATCH');
  });
  it('未登录、他人、删除、未知记录与伪造参数拒绝，文字记录不冒充附件', async (): Promise<void> => {
    const other = (await login(await register())).accessToken;
    const extractor = jest.spyOn(app.get(DocumentTextExtractor),'extract');
    expect((await request(`/ingestion/${id}/preview`,{})).status).toBe(401);
    expect((await preview(other)).status).toBe(403); expect((await preview(access,randomUUID())).status).toBe(403);
    expect((await preview(access,'bad')).status).toBe(400);
    for (const body of [{url:'https://example.invalid/private'},{userId:account.id},{text:'伪造正文'},[]]) {
      expect((await request(`/ingestion/${id}/preview`,body,access)).status).toBe(400);
    }
    const text = await request('/ingestion/wechat',{rawContent:'虚构文字'},access);
    expect((await preview(access,text.data.id as string)).status).toBe(403);
    await repository.db.ingestionRecord.update({where:{id},data:{deletedAt:new Date()}});
    expect((await preview()).status).toBe(403); expect(extractor).not.toHaveBeenCalled();
  });
  it('读取失败、缺失/变化的对象只记录固定原因，原件恢复后可重试', async (): Promise<void> => {
    const read = jest.spyOn(storage(),'read').mockRejectedValueOnce(new Error('fictional-private-storage'));
    const failed = await preview(); expect(failed.status).toBe(201);
    expect(failed.data).toMatchObject({extraction:{state:'MANUAL_REQUIRED',reason:'UNAVAILABLE',retryable:true},suggestion:null});
    expect(failed.raw.includes('fictional-private-storage')).toBe(false); read.mockRestore();
    const stat = jest.spyOn(storage(),'stat').mockResolvedValueOnce(null)
      .mockResolvedValueOnce({sizeBytes:1,mimeType:'application/pdf',etag:'abcd'})
      .mockResolvedValueOnce({sizeBytes:fictionalPdf().length,mimeType:'image/png',etag:'abcd'});
    for (let i=0;i<3;i++) expect((await preview()).data.extraction).toMatchObject({reason:'UNAVAILABLE'});
    stat.mockRestore(); expect((await preview()).data.extraction).toMatchObject({state:'TEXT'});
    const logs = await repository.db.auditLog.findMany({where:{resourceId:id,action:'INGESTION_PREVIEW_FINISHED'}});
    expect(logs).toHaveLength(5); expect(JSON.stringify(logs).includes('fictional-private-storage')).toBe(false);
  });
  it('扫描式空正文、损坏文件、不支持格式和超大原件均明确降级，保留待定资料', async (): Promise<void> => {
    for (const [bytes,mime,reason] of [[fictionalPdf(''),'application/pdf','NO_TEXT'],
      [Buffer.from('%PDF-1.7\ninvalid fictional'),'application/pdf','INVALID_DOCUMENT'],
      [Buffer.from('fictional image'),'image/png','UNSUPPORTED_FORMAT'],
      [Buffer.alloc(10*1024*1024+1,32),'application/pdf','FILE_TOO_LARGE']] as const) {
      const item = await receiveFile(access,bytes,mime); const result = await preview(access,item);
      expect(result.data).toMatchObject({extraction:{state:'MANUAL_REQUIRED',reason,retryable:false},suggestion:null});
      expect((await request(`/ingestion/${item}`,undefined,access)).data.status).toBe('PENDING_MATCH');
    }
  });
  it('同用户并发拒绝，解析后删除会再次拒绝且不泄露正文，槽位随后释放', async (): Promise<void> => {
    let release!: (value:ExtractionResult)=>void; let entered!: ()=>void;
    const ready = new Promise<void>((resolve): void => {entered=resolve;});
    const spy = jest.spyOn(app.get(DocumentTextExtractor),'extract').mockImplementationOnce(async (): Promise<ExtractionResult> => {
      entered(); return new Promise((resolve): void => {release=resolve;});
    });
    const pending = preview(); await ready;
    expect((await preview()).status).toBe(429);
    await repository.db.ingestionRecord.update({where:{id},data:{deletedAt:new Date()}});
    release({state:'TEXT',text:'不可泄露虚构正文'});
    const result = await pending; expect(result.status).toBe(403); expect(result.raw.includes('不可泄露虚构正文')).toBe(false);
    spy.mockRestore();
    const fresh = await receiveFile(access,fictionalPdf('Another fictional document'),'application/pdf');
    expect((await preview(access,fresh)).data.extraction).toMatchObject({state:'TEXT'});
    expect(await repository.db.auditLog.count({where:{resourceId:id,action:'INGESTION_PREVIEW_STARTED'}})).toBe(1);
    expect(await repository.db.auditLog.count({where:{resourceId:id,action:'INGESTION_PREVIEW_FINISHED'}})).toBe(0);
  });
  it('失败尝试保留而非标为管道完成，忽略记录预览不恢复；异常后仍可重试', async (): Promise<void> => {
    await request(`/ingestion/${id}/ignore`,{},access);
    const spy = jest.spyOn(app.get(DocumentTextExtractor),'extract').mockRejectedValueOnce(new Error('private-parser'))
      .mockResolvedValueOnce({state:'MANUAL_REQUIRED',reason:'TIMEOUT',retryable:true});
    expect((await preview()).data.extraction).toMatchObject({reason:'UNAVAILABLE'});
    expect((await preview()).data.extraction).toMatchObject({reason:'TIMEOUT',retryable:true});
    spy.mockRestore(); expect((await preview()).data.extraction).toMatchObject({state:'TEXT'});
    expect((await request(`/ingestion/${id}`,undefined,access)).data.status).toBe('IGNORED');
  });
  it('单实例最多两份解析，第三位用户被拒绝；完成后可重新申请', async (): Promise<void> => {
    const second = (await login(await register())).accessToken;
    const third = (await login(await register())).accessToken;
    const secondId = await receiveFile(second,fictionalPdf(),'application/pdf');
    const thirdId = await receiveFile(third,fictionalPdf(),'application/pdf');
    const releases: Array<(value:ExtractionResult)=>void> = []; let entered!: ()=>void;
    const ready = new Promise<void>((resolve): void => {entered=resolve;});
    const spy = jest.spyOn(app.get(DocumentTextExtractor),'extract').mockImplementation(async (): Promise<ExtractionResult> => {
      return new Promise((resolve): void => {releases.push(resolve); if(releases.length===2) entered();});
    });
    const running = [preview(),preview(second,secondId)]; await ready;
    try { expect((await preview(third,thirdId)).status).toBe(429); }
    finally { for (const release of releases) release({state:'MANUAL_REQUIRED',reason:'NO_TEXT',retryable:false}); }
    expect((await Promise.all(running)).map((result): number => result.status)).toEqual([201,201]);
    spy.mockRestore(); expect((await preview(third,thirdId)).data.extraction).toMatchObject({state:'TEXT'});
  });
  it('开始审计失败不启动解析、不泄露错误，释放槽位后可以重试', async (): Promise<void> => {
    const extract = jest.spyOn(app.get(DocumentTextExtractor),'extract');
    const transaction = jest.spyOn(repository.db,'$transaction').mockRejectedValueOnce(new Error('fictional-private-audit'));
    const result = await preview(); transaction.mockRestore();
    expect(result.status).toBe(500); expect(result.raw.includes('fictional-private-audit')).toBe(false);
    expect(extract).not.toHaveBeenCalled();
    expect((await preview()).data.extraction).toMatchObject({state:'TEXT'});
  });
});
