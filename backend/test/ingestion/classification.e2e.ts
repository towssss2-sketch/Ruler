import { createHash, randomUUID } from 'node:crypto';
import { app, baseUrl, login, register, repository, request } from '../auth/fixture';
import { installDocumentFixture, uploadInput } from '../document/fixture';
import { storageFetch } from '../storage/minio-fixture';
import { complete } from './file-fixture';
import { fictionalDocx } from './text-fixtures';
import { DOCX_MIME } from '../../src/modules/ingestion/extraction/extraction-result';
import { PreviewAttemptService } from '../../src/modules/ingestion/extraction/preview-attempt.service';
import { PreviewClassificationService } from '../../src/modules/ingestion/extraction/preview-classification.service';
import { PrismaRepository } from '../../src/prisma.repository';
import * as rules from '../../src/modules/ingestion/extraction/document-rules';

installDocumentFixture();
afterEach((): void => { jest.restoreAllMocks(); });

async function fixture(text: string): Promise<{ userId: string; access: string; id: string; email: string }> {
  const owner = await register(), access = (await login(owner)).accessToken, bytes = fictionalDocx(text);
  const offer = await request('/ingestion/files/presign', uploadInput({ fileName: '虚构分类.docx', mimeType: DOCX_MIME,
    sizeBytes: bytes.length, contentMd5: createHash('md5').update(bytes).digest('base64') }), access);
  expect(offer.status).toBe(201);
  const upload = await storageFetch(offer.data.url as string, { method: 'PUT', headers: offer.data.headers as Record<string, string>, body: Uint8Array.from(bytes) });
  expect(upload.status).toBe(200); await upload.arrayBuffer();
  const received = await complete(access, offer.data.uploadId as string); expect(received.status).toBe(201);
  return { userId: owner.id, access, id: received.data.id as string, email: owner.email };
}
function path(id: string, attemptId: string): string { return `/ingestion/${id}/preview-attempts/${attemptId}/classification`; }

describe('规则分类结果持久化', (): void => {
  it.each([
    ['民事起诉状', 'PLEADING'], ['民事答辩状', 'DEFENSE'], ['民事裁定书', 'COURT_DOCUMENT'],
    ['传票', 'SUMMONS'], ['法律服务合同', 'SERVICE_CONTRACT'],
  ])('真实 DOCX %s 分类在重登/新连接后保留，仅返回固定元数据', async (title, category): Promise<void> => {
    const f = await fixture(`${title}\n(2026)虚构民初123号\n仅用于分类持久化的虚构正文`);
    const before = await repository.db.ingestionRecord.findUniqueOrThrow({ where: { id: f.id } });
    const quota = (await repository.db.user.findUniqueOrThrow({ where: { id: f.userId } })).storageUsedBytes;
    const preview = await request(`/ingestion/${f.id}/preview`, {}, f.access); expect(preview.status).toBe(201);
    const attemptId = preview.data.attemptId as string;
    const access = (await login({ id: f.userId, email: f.email })).accessToken;
    const expected = { attemptId, state: 'RECORDED', classification: {
      category, ruleVersion: 'title-v1', reason: 'TITLE_MATCH', requiresConfirmation: true } };
    const response = await fetch(`${baseUrl}${path(f.id, attemptId)}`, { headers: { authorization: `Bearer ${access}` } });
    expect(response.status).toBe(200); expect(response.headers.get('cache-control')).toBe('private, no-store');
    expect((await request(path(f.id, attemptId), undefined, access)).data).toEqual(expected);
    const fresh = new PrismaRepository();
    try {
      expect(await new PreviewClassificationService(fresh, new PreviewAttemptService(fresh)).read(f.userId, f.id, attemptId)).toEqual(expected);
    } finally { await fresh.onModuleDestroy(); }
    const saved = await repository.db.ingestionPreviewAttempt.findUniqueOrThrow({ where: { id: attemptId } });
    expect(saved).toMatchObject({ classificationCategory: category, classificationReason: 'TITLE_MATCH', classificationRuleVersion: 'title-v1' });
    for (const secret of ['虚构民初123', '仅用于分类持久化', '虚构分类.docx', 'caseNumbers', 'storageKey']) {
      expect(JSON.stringify(saved).includes(secret)).toBe(false);
      expect(JSON.stringify(expected).includes(secret)).toBe(false);
    }
    expect(await repository.db.ingestionRecord.findUniqueOrThrow({ where: { id: f.id } })).toEqual(before);
    expect((await repository.db.user.findUniqueOrThrow({ where: { id: f.userId } })).storageUsedBytes).toBe(quota);
    expect(await repository.db.document.count({ where: { ingestionId: f.id } })).toBe(0);
  });

  it('未识别与标题冲突均保存明确结果，读取历史不重新运行规则或生成尝试', async (): Promise<void> => {
    for (const [text, reason] of [['虚构无标题正文', 'NO_TITLE'], ['民事起诉状\n民事答辩状', 'CONFLICTING_TITLES']]) {
      const f = await fixture(text!);
      const preview = await request(`/ingestion/${f.id}/preview`, {}, f.access); expect(preview.status).toBe(201);
      const attemptId = preview.data.attemptId as string;
      const spy = jest.spyOn(rules, 'suggestDocument').mockImplementation((): never => { throw new Error('不得重算历史'); });
      try {
        for (let i = 0; i < 2; i++) {
          const result = await request(path(f.id, attemptId), undefined, f.access);
          expect(result.status).toBe(200);
          expect(result.data).toMatchObject({ state: 'RECORDED', classification: { category: null, reason, requiresConfirmation: true } });
        }
        expect(spy).not.toHaveBeenCalled();
      } finally { spy.mockRestore(); }
      expect(await repository.db.ingestionPreviewAttempt.count({ where: { ingestionId: f.id } })).toBe(1);
      expect(await repository.db.auditLog.count({ where: { resourceId: f.id, action: 'INGESTION_PREVIEW_FINISHED' } })).toBe(1);
    }
  });

  it('未知/他人/错配尝试/删除/停用及伪造参数拒绝，不读取越权分类', async (): Promise<void> => {
    const f = await fixture('民事起诉状'), other = await fixture('民事答辩状');
    const preview = await request(`/ingestion/${f.id}/preview`, {}, f.access), attemptId = preview.data.attemptId as string;
    expect((await request(path(f.id, attemptId))).status).toBe(401);
    expect((await request(path(f.id, attemptId), undefined, other.access)).status).toBe(403);
    expect((await request(path(other.id, attemptId), undefined, other.access)).status).toBe(403);
    expect((await request(path(f.id, randomUUID()), undefined, f.access)).status).toBe(403);
    expect((await request(path(randomUUID(), attemptId), undefined, f.access)).status).toBe(403);
    expect((await request(path(f.id, 'bad'), undefined, f.access)).status).toBe(400);
    for (const query of ['?category=OTHER', '?userId=x', '?__proto__=x', '?page=1&page=1']) {
      expect((await request(path(f.id, attemptId) + query, undefined, f.access)).status).toBe(400);
    }
    await repository.db.user.update({ where: { id: f.userId }, data: { deletedAt: new Date() } });
    await expect(app.get(PreviewClassificationService).read(f.userId, f.id, attemptId)).rejects.toMatchObject({ status: 403 });
    await repository.db.user.update({ where: { id: f.userId }, data: { deletedAt: null } });
    await repository.db.ingestionRecord.update({ where: { id: f.id }, data: { deletedAt: new Date() } });
    expect((await request(path(f.id, attemptId), undefined, f.access)).status).toBe(403);
  });

  it('旧成功记录不回填；处理中/失败/中断不误报分类，重复提取不改旧结果', async (): Promise<void> => {
    const f = await fixture('法律服务合同'), now = new Date(), attempts = app.get(PreviewAttemptService);
    const old = await repository.db.ingestionPreviewAttempt.create({ data: { userId: f.userId, ingestionId: f.id,
      status: 'SUCCEEDED', startedAt: now, finishedAt: now, leaseExpiresAt: new Date(now.getTime() + 120000) } });
    expect((await request(path(f.id, old.id), undefined, f.access)).data).toEqual({ attemptId: old.id, state: 'NOT_RECORDED', classification: null });
    const running = await attempts.begin(f.userId, f.id);
    expect((await request(path(f.id, running.attemptId), undefined, f.access)).data.state).toBe('NOT_AVAILABLE');
    await attempts.finish(f.userId, f.id, running.attemptId, { state: 'MANUAL_REQUIRED', reason: 'TIMEOUT', retryable: true });
    expect((await request(path(f.id, running.attemptId), undefined, f.access)).data.classification).toBeNull();
    const interrupted = await repository.db.ingestionPreviewAttempt.create({ data: { userId: f.userId, ingestionId: f.id,
      status: 'INTERRUPTED', startedAt: new Date(now.getTime() - 120000), finishedAt: now, leaseExpiresAt: now } });
    expect((await request(path(f.id, interrupted.id), undefined, f.access)).data.state).toBe('NOT_AVAILABLE');
    const a = await request(`/ingestion/${f.id}/preview`, {}, f.access), b = await request(`/ingestion/${f.id}/preview`, {}, f.access);
    expect(a.status).toBe(201); expect(b.status).toBe(201); expect(a.data.attemptId).not.toBe(b.data.attemptId);
    await request(`/ingestion/${f.id}/ignore`, {}, f.access);
    for (const attemptId of [a.data.attemptId, b.data.attemptId]) {
      expect((await request(path(f.id, attemptId as string), undefined, f.access)).data).toMatchObject({ state: 'RECORDED', classification: { category: 'SERVICE_CONTRACT' } });
    }
    expect((await request(path(f.id, old.id), undefined, f.access)).data.state).toBe('NOT_RECORDED');
  });

  it('结束审计真实写入失败时分类与成功状态一起回滚，不返回正文或伪成功', async (): Promise<void> => {
    const f = await fixture('民事起诉状\n仅用于回滚的虚构正文');
    await repository.db.$executeRaw`CREATE FUNCTION ruler_test_fail_classification_audit() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN IF NEW.action = 'INGESTION_PREVIEW_FINISHED' THEN RAISE EXCEPTION 'fictional audit failure'; END IF; RETURN NEW; END $$`;
    try {
      await repository.db.$executeRaw`CREATE TRIGGER ruler_test_classification_audit BEFORE INSERT ON "AuditLog"
        FOR EACH ROW EXECUTE FUNCTION ruler_test_fail_classification_audit()`;
      try {
        const result = await request(`/ingestion/${f.id}/preview`, {}, f.access);
        expect(result.status).toBe(500); expect(result.raw.includes('仅用于回滚')).toBe(false);
        const row = await repository.db.ingestionPreviewAttempt.findFirstOrThrow({ where: { ingestionId: f.id } });
        expect(row).toMatchObject({ status: 'RUNNING', classificationCategory: null, classificationReason: null, classificationRuleVersion: null });
        expect((await request(path(f.id, row.id), undefined, f.access)).data.state).toBe('NOT_AVAILABLE');
        expect(await repository.db.auditLog.count({ where: { resourceId: f.id, action: 'INGESTION_PREVIEW_FINISHED' } })).toBe(0);
      } finally { await repository.db.$executeRaw`DROP TRIGGER ruler_test_classification_audit ON "AuditLog"`; }
    } finally { await repository.db.$executeRaw`DROP FUNCTION ruler_test_fail_classification_audit()`; }
  });
});
