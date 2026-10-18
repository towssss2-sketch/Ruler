import { DocumentCategory } from '@prisma/client';
import { installDocumentFixture, offer, uploadInput } from './fixture';
import { register, login, createCase, request, repository } from '../auth/fixture';

installDocumentFixture();

describe('文件分类真实上传与持久化', (): void => {
  it.each(Object.values(DocumentCategory))('分类 %s 可上传登记、按类读取并落库', async (category): Promise<void> => {
    const account = await register();
    const tokens = await login(account);
    const caseId = await createCase(account.id);
    const ticket = await offer(tokens.accessToken, caseId, uploadInput({ fileName: `fictional-${category}.pdf` }));
    const saved = await request(`/cases/${caseId}/documents`, { uploadId: ticket.uploadId, category }, tokens.accessToken);
    expect(saved.status).toBe(201);
    expect(saved.data.category).toBe(category);
    const persisted = await repository.db.document.findUniqueOrThrow({ where: { id: saved.data.id as string } });
    expect(persisted.category).toBe(category);
    const page = await request(`/cases/${caseId}/documents?category=${category}`, undefined, tokens.accessToken);
    expect(page.status).toBe(200);
    expect(page.data.total).toBe(1);
    const other = category === 'OTHER' ? 'EVIDENCE' : 'OTHER';
    expect((await request(`/cases/${caseId}/documents?category=${other}`, undefined, tokens.accessToken)).data.total).toBe(0);
  });
  it('缺少或未知分类不登记，原票据仍能按明确分类完成', async (): Promise<void> => {
    const account = await register();
    const tokens = await login(account);
    const caseId = await createCase(account.id);
    const ticket = await offer(tokens.accessToken, caseId);
    for (const category of [undefined, '', 'UNKNOWN', '法院文件']) {
      expect((await request(`/cases/${caseId}/documents`, { uploadId: ticket.uploadId, category }, tokens.accessToken)).status).toBe(400);
    }
    expect(await repository.db.document.count({ where: { caseId } })).toBe(0);
    expect((await request(`/cases/${caseId}/documents`, { uploadId: ticket.uploadId, category: 'COURT_DOCUMENT' }, tokens.accessToken)).status).toBe(201);
  });
});
