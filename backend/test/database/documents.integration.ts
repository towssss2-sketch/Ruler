import { Prisma, IngestionRecord, Case } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { client, cipher, createCase, createUser, createDocument } from './fixtures';

afterAll(async (): Promise<void> => { await client.$disconnect(); });

async function createIngestion(caseRecord: Case, value = `虚构归集材料-${randomUUID()}`): Promise<IngestionRecord> {
  const id = randomUUID();
  return client.ingestionRecord.create({ data: {
    id, userId: caseRecord.ownerId, channel: 'SMS',
    rawContent: cipher.encrypt(value, `IngestionRecord:${id}:rawContent`),
    deliveryLink: cipher.encrypt('https://delivery.example.invalid/fictional', `IngestionRecord:${id}:deliveryLink`),
    contentHash: Buffer.from(cipher.blindIndex(value, `IngestionRecord:${caseRecord.ownerId}:SMS`)).toString('hex'),
    status: 'MATCHED', matchedCaseId: caseRecord.id,
  } });
}

describe('文件版本与跨案关联', (): void => {
  it('同一文件只能有一个活跃当前版本，版本号和容量合法', async (): Promise<void> => {
    const caseRecord = await createCase(await createUser());
    const original = await createDocument(caseRecord);
    const data = { caseId: original.caseId, uploadedBy: original.uploadedBy, category: original.category,
      fileName: original.fileName, mimeType: original.mimeType, sizeBytes: original.sizeBytes, versionGroupId: original.versionGroupId };
    await expect(client.document.create({ data: { ...data, storageKey: `schema-fixture/${randomUUID()}`, version: 2 } }))
      .rejects.toMatchObject({ code: 'P2002' });
    await expect(client.document.create({ data: { ...data, versionGroupId: randomUUID(), storageKey: `schema-fixture/${randomUUID()}`,
      sizeBytes: -1n } })).rejects.toThrow();
    await expect(client.document.create({ data: { ...data, versionGroupId: randomUUID(), storageKey: `schema-fixture/${randomUUID()}`,
      version: 0 } })).rejects.toThrow();
    const [, current] = await client.$transaction([
      client.document.update({ where: { id: original.id }, data: { isCurrentVersion: false } }),
      client.document.create({ data: { ...data, storageKey: `schema-fixture/${randomUUID()}`, version: 2 } }),
    ]);
    expect(current.isCurrentVersion).toBe(true);
    expect(current.isClientVisible).toBe(false);
  });
  it('A 案件时间轴不能引用 B 案件文件', async (): Promise<void> => {
    const user = await createUser();
    const a = await createCase(user);
    const b = await createCase(user);
    const document = await createDocument(b);
    await expect(client.timelineEvent.create({ data: { caseId: a.id, title: '虚构时间轴',
      eventDate: new Date('2026-10-14'), sourceDocumentId: document.id } })).rejects.toMatchObject({ code: 'P2003' });
  });
  it('文书定稿必须关联本案件的文档，不能用外案文档伪定稿', async (): Promise<void> => {
    const user = await createUser();
    const a = await createCase(user);
    const b = await createCase(user);
    const document = await createDocument(b);
    const id = randomUUID();
    const data = { id, caseId: a.id, createdBy: user.id, docType: 'DEFENSE' as const, modelVersion: 'fictional-model',
      content: cipher.encrypt(JSON.stringify({ text: '虚构测试初稿' }), `DocumentDraft:${id}:content`) };
    await expect(client.documentDraft.create({ data: { ...data, status: 'ADOPTED', adoptedDocumentId: document.id } }))
      .rejects.toMatchObject({ code: 'P2003' });
    await expect(client.documentDraft.create({ data: { ...data, status: 'ADOPTED' } })).rejects.toThrow();
    const draft = await client.documentDraft.create({ data });
    expect(draft.status).toBe('DRAFT');
  });
});

describe('材料归集一致性与待定区', (): void => {
  it('同一用户/渠道/内容判重，同时保留加密原文与送达链接', async (): Promise<void> => {
    const caseRecord = await createCase(await createUser());
    const value = `虚构重复材料-${randomUUID()}`;
    const first = await createIngestion(caseRecord, value);
    await expect(createIngestion(caseRecord, value)).rejects.toMatchObject({ code: 'P2002' });
    expect(cipher.decrypt(first.rawContent, `IngestionRecord:${first.id}:rawContent`)).toBe(value);
    expect(cipher.decrypt(first.deliveryLink!, `IngestionRecord:${first.id}:deliveryLink`)).toContain('example.invalid');
  });
  it('文档不能绑定不同案件或不同渠道的归集来源', async (): Promise<void> => {
    const user = await createUser();
    const a = await createCase(user);
    const b = await createCase(user);
    const record = await createIngestion(a);
    const base: Prisma.DocumentUncheckedCreateInput = { caseId: b.id, uploadedBy: user.id, category: 'OTHER',
      storageKey: `schema-fixture/${randomUUID()}`, fileName: '虚构.txt', mimeType: 'text/plain',
      sizeBytes: 10n, source: 'SMS', ingestionId: record.id };
    await expect(client.document.create({ data: base })).rejects.toThrow();
    await expect(client.document.create({ data: { ...base, caseId: a.id, source: 'EMAIL' } })).rejects.toThrow();
  });
  it('移出案件时不能留下活跃外案文件，软删除后可退回待定并保留来源历史', async (): Promise<void> => {
    const caseRecord = await createCase(await createUser());
    const record = await createIngestion(caseRecord);
    const document = await client.document.create({ data: { caseId: caseRecord.id, uploadedBy: caseRecord.ownerId,
      category: 'OTHER', fileName: '虚构.txt', storageKey: `schema-fixture/${randomUUID()}`,
      mimeType: 'text/plain', sizeBytes: 10n, source: 'SMS', ingestionId: record.id } });
    await expect(client.ingestionRecord.update({ where: { id: record.id }, data: { matchedCaseId: null, status: 'PENDING_MATCH' } }))
      .rejects.toThrow();
    await client.$transaction([
      client.document.update({ where: { id: document.id }, data: { deletedAt: new Date() } }),
      client.ingestionRecord.update({ where: { id: record.id }, data: { matchedCaseId: null, status: 'PENDING_MATCH' } }),
    ]);
    expect((await client.document.findUniqueOrThrow({ where: { id: document.id } })).ingestionId).toBe(record.id);
    expect((await client.ingestionRecord.findUniqueOrThrow({ where: { id: record.id } })).matchedCaseId).toBeNull();
  });
});
