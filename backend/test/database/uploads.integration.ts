import { randomUUID } from 'node:crypto';
import { Prisma } from '@prisma/client';
import { client, createCase, createUser } from './fixtures';

afterAll(async (): Promise<void> => { await client.$disconnect(); });

/** 构造仅用于数据库约束的上传票据，不宣称执行对象上传。 */
async function ticketInput(): Promise<Prisma.DocumentUploadUncheckedCreateInput> {
  const owner = await createUser(); const record = await createCase(owner); const id = randomUUID();
  return { caseId: record.id, ownerId: owner.id, uploadedBy: owner.id, documentId: id, versionGroupId: randomUUID(),
    version: 1, fileName: '虚构.pdf', mimeType: 'application/pdf', sizeBytes: 1, contentMd5: '1B2M2Y8AsgTpgAmY7PhCfg==',
    pendingKey: `${owner.id}/${record.id}/${randomUUID()}/1_虚构.pdf`, storageKey: `${owner.id}/${record.id}/${id}/1_虚构.pdf`,
    expiresAt: new Date(Date.now() + 600000) };
}

describe('上传票据的实际 PostgreSQL 约束', (): void => {
  it('所有者、案件和用户外键不可伪造；票据大小和版本有界', async (): Promise<void> => {
    const data = await ticketInput();
    for (const change of [{ ownerId: randomUUID() }, { caseId: randomUUID() }, { uploadedBy: randomUUID() },
      { sizeBytes: 0 }, { sizeBytes: 209715201 }, { version: 0 }]) {
      await expect(client.documentUpload.create({ data: { ...data, ...change } })).rejects.toThrow();
    }
  });
  it('正式与临时对象必须隔离，归集来源不能缺少 ID，手工来源不能夹带 ID', async (): Promise<void> => {
    const data = await ticketInput();
    for (const change of [{ pendingKey: data.storageKey }, { source: 'SMS' as const }, { ingestionId: randomUUID() }]) {
      await expect(client.documentUpload.create({ data: { ...data, ...change } })).rejects.toThrow();
    }
  });
  it('票据的对象身份、大小、有效期和归属不能更新，完成/清理状态可以推进', async (): Promise<void> => {
    const ticket = await client.documentUpload.create({ data: await ticketInput() });
    for (const data of [{ sizeBytes: 2 }, { storageKey: 'fictional-replacement' }, { expiresAt: new Date(0) }, { documentId: randomUUID() }]) {
      await expect(client.documentUpload.update({ where: { id: ticket.id }, data })).rejects.toThrow();
    }
    await expect(client.documentUpload.update({ where: { id: ticket.id }, data: { completedAt: new Date() } })).resolves.toBeDefined();
  });
  it('同一逻辑文件不能分配重复版本，也不能复用正式对象或文档 ID', async (): Promise<void> => {
    const data = await ticketInput(); await client.documentUpload.create({ data });
    await expect(client.documentUpload.create({ data: { ...data, pendingKey: `fictional-${randomUUID()}` } })).rejects.toThrow();
    await expect(client.documentUpload.create({ data: { ...data, documentId: randomUUID(),
      pendingKey: `fictional-${randomUUID()}`, storageKey: `fictional-${randomUUID()}` } })).rejects.toThrow();
  });
});
