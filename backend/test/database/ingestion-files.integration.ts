import { randomBytes, randomUUID } from 'node:crypto';
import { Prisma } from '@prisma/client';
import { client, createUser, cipher } from './fixtures';

afterAll(async (): Promise<void> => { await client.$disconnect(); });

/** 仅构造数据库约束夹具，不代替真实对象测试。 */
async function fixtures(): Promise<{ ticket: Prisma.IngestionUploadUncheckedCreateInput; ingestionId: string }> {
  const user = await createUser(); const id = randomUUID();
  await client.ingestionRecord.create({ data: { id, userId: user.id, channel: 'WECHAT', contentHash: randomBytes(32).toString('hex'),
    rawContent: cipher.encrypt('虚构暂存', `IngestionRecord:${id}:rawContent`) } });
  return { ingestionId: id, ticket: { userId: user.id, fileName: '虚构.pdf', mimeType: 'application/pdf',
    sizeBytes: 1, contentMd5: '1B2M2Y8AsgTpgAmY7PhCfg==', pendingKey: `fixture/${randomUUID()}`,
    storageKey: `fixture/${randomUUID()}`, expiresAt: new Date(Date.now() + 600000) } };
}

describe('归集文件与上传票据实际数据库约束', (): void => {
  it('大小、临时/正式对象隔离、完成标记与归集关联必须有效', async (): Promise<void> => {
    const { ticket, ingestionId } = await fixtures();
    for (const changes of [{ sizeBytes: 0 }, { sizeBytes: 209715201 }, { pendingKey: ticket.storageKey },
      { ingestionId }, { completedAt: new Date() }, { userId: randomUUID() }]) {
      await expect(client.ingestionUpload.create({ data: { ...ticket, ...changes } })).rejects.toThrow();
    }
  });
  it('附件和完成票据不得关联其他用户的归集记录', async (): Promise<void> => {
    const a = await fixtures(); const b = await fixtures();
    await expect(client.ingestionUpload.create({ data: { ...a.ticket, ingestionId: b.ingestionId, completedAt: new Date() } })).rejects.toThrow();
    await expect(client.ingestionFile.create({ data: { userId: a.ticket.userId, ingestionId: b.ingestionId,
      fileName: '虚构.pdf', mimeType: 'application/pdf', sizeBytes: 1, storageKey: `fixture/${randomUUID()}` } })).rejects.toThrow();
  });
  it('身份、对象和期限不可改；完成及清理结果只能向前', async (): Promise<void> => {
    const { ticket, ingestionId } = await fixtures(); const row = await client.ingestionUpload.create({ data: ticket });
    for (const data of [{ sizeBytes: 2 }, { expiresAt: new Date(0) }, { userId: randomUUID() }, { pendingKey: 'replacement' }]) {
      await expect(client.ingestionUpload.update({ where: { id: row.id }, data })).rejects.toThrow();
    }
    await client.ingestionUpload.update({ where: { id: row.id }, data: { ingestionId, completedAt: new Date(), cleanedAt: new Date() } });
    for (const data of [{ completedAt: null, ingestionId: null }, { cleanedAt: null }, { ingestionId: randomUUID() }]) {
      await expect(client.ingestionUpload.update({ where: { id: row.id }, data })).rejects.toThrow();
    }
    const expired = await client.ingestionUpload.create({ data: { ...ticket, pendingKey: randomUUID(), storageKey: randomUUID(), cleanedAt: new Date() } });
    await expect(client.ingestionUpload.update({ where: { id: expired.id }, data: { ingestionId, completedAt: new Date() } })).rejects.toThrow();
  });
  it('附件一对一且身份不可改，重复存储键不可复用', async (): Promise<void> => {
    const { ticket, ingestionId } = await fixtures();
    const data = { userId: ticket.userId, ingestionId, fileName: '虚构.pdf', mimeType: 'application/pdf', sizeBytes: 1, storageKey: ticket.storageKey };
    const file = await client.ingestionFile.create({ data });
    await expect(client.ingestionFile.create({ data: { ...data, storageKey: randomUUID() } })).rejects.toThrow();
    for (const changes of [{ storageKey: randomUUID() }, { sizeBytes: 2 }, { fileName: '换名.pdf' }, { ingestionId: randomUUID() }]) {
      await expect(client.ingestionFile.update({ where: { id: file.id }, data: changes })).rejects.toThrow();
    }
  });
});
