import { randomBytes, randomUUID } from 'node:crypto';
import { app, repository } from '../auth/fixture';
import { EncryptionService } from '../../src/encryption.service';

/** 建立虚构关联图验证级联归档；文件元数据仅作测试准备，不宣称上传业务已完成。 */
export async function linkedRecords(userId: string, caseId: string): Promise<{ accessId: string; ingestionId: string }> {
  const cipher = app.get(EncryptionService);
  const party = await repository.db.caseParty.findFirstOrThrow({ where: { caseId } });
  const ingestionId = randomUUID();
  await repository.db.ingestionRecord.create({ data: { id: ingestionId, userId, matchedCaseId: caseId,
    channel: 'SMS', status: 'MATCHED', contentHash: randomBytes(32).toString('hex'),
    rawContent: cipher.encrypt('虚构短信', `IngestionRecord:${ingestionId}:rawContent`), nextRetryAt: new Date() } });
  const document = await repository.db.document.create({ data: { caseId, uploadedBy: userId, category: 'OTHER',
    fileName: '虚构.pdf', storageKey: `fictional/${randomUUID()}`, sizeBytes: 10, mimeType: 'application/pdf',
    source: 'SMS', ingestionId } });
  await repository.db.task.createMany({ data: [{ caseId, title: '虚构未完成' },
    { caseId, title: '虚构已完成', status: 'DONE', completedAt: new Date() },
    { caseId, title: '虚构已删除', deletedAt: new Date() }] });
  await repository.db.document.createMany({ data: [{ caseId, uploadedBy: userId, category: 'OTHER', fileName: '旧版.pdf',
    storageKey: `fictional/${randomUUID()}`, sizeBytes: 10, mimeType: 'application/pdf', isCurrentVersion: false },
  { caseId, uploadedBy: userId, category: 'OTHER', fileName: '已删除.pdf', storageKey: `fictional/${randomUUID()}`,
    sizeBytes: 10, mimeType: 'application/pdf', deletedAt: new Date() }] });
  await repository.db.timelineEvent.create({ data: { caseId, title: '虚构事件', eventDate: new Date(), sourceDocumentId: document.id } });
  const analysisId = randomUUID();
  await repository.db.caseAnalysis.create({ data: { id: analysisId, caseId, modelVersion: 'fictional-test',
    summary: cipher.encrypt('虚构分析', `CaseAnalysis:${analysisId}:summary`) } });
  const draftId = randomUUID();
  await repository.db.documentDraft.create({ data: { id: draftId, caseId, createdBy: userId, docType: 'DEFENSE',
    modelVersion: 'fictional-test', content: cipher.encrypt('虚构草稿', `DocumentDraft:${draftId}:content`) } });
  const access = await repository.db.clientAccess.create({ data: { caseId, casePartyId: party.id, grantedBy: userId,
    tokenHash: randomBytes(32), status: 'ACTIVE', expiresAt: new Date(Date.now() + 60000) } });
  await repository.db.clientAccessLog.create({ data: { caseId, clientAccessId: access.id, action: 'FICTIONAL_READ',
    resourceType: 'Case', succeeded: true } });
  return { accessId: access.id, ingestionId };
}
