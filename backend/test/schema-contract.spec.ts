import { Prisma } from '@prisma/client';

const businessModels = [
  'User', 'Case', 'CaseParty', 'CaseMember', 'Document', 'IngestionRecord',
  'Task', 'TimelineEvent', 'CaseAnalysis', 'DocumentDraft', 'EmailBinding',
  'DeliveryPlatformRule', 'ClientAccess', 'ClientAccessLog', 'AuditLog',
  'RTWallet', 'RTTransaction', 'PriceConfig',
  'AuthSession', 'RefreshCredential',
];

function model(name: string): Prisma.DMMF.Model {
  const result = Prisma.dmmf.datamodel.models.find((value): boolean => value.name === name);
  if (!result) throw new Error(`缺少业务实体：${name}`);
  return result;
}

describe('原始需求实体与通用列契约', (): void => {
  it('全部业务实体、鉴权实体、上传票据及阶段 0 探针均存在', (): void => {
    expect(Prisma.dmmf.datamodel.models.map((value): string => value.name).sort())
      .toEqual([...businessModels, 'DocumentUpload', 'EnvironmentProbe'].sort());
  });
  it.each(businessModels)('%s 保留 UUID 主键、创建/更新/软删除列', (name: string): void => {
    const value = model(name);
    const id = value.fields.find((field): boolean => field.name === 'id')!;
    expect(id).toMatchObject({ isId: true, type: 'String', hasDefaultValue: true });
    // Prisma 元数据会将 uuid() 的默认版本展开为 v4。
    expect(id.default).toEqual({ name: 'uuid', args: [4] });
    for (const column of ['createdAt', 'updatedAt', 'deletedAt']) {
      expect(value.fields.find((field): boolean => field.name === column)?.type).toBe('DateTime');
    }
    expect(value.fields.find((field): boolean => field.name === 'deletedAt')?.isRequired).toBe(false);
  });
});

describe('指定敏感字段的密文类型与标记', (): void => {
  it.each([
    ['User', 'phone'], ['Case', 'clerkPhone'],
    ['CaseParty', 'idCard'], ['CaseParty', 'phone'],
    ['IngestionRecord', 'rawContent'], ['IngestionRecord', 'deliveryLink'],
    ['EmailBinding', 'credentials'], ['DocumentDraft', 'content'], ['CaseAnalysis', 'summary'],
  ])('%s.%s 不以明文字符串或 JSON 建模', (entity: string, column: string): void => {
    const field = model(entity).fields.find((value): boolean => value.name === column)!;
    expect(field.type).toBe('Bytes');
    expect(field.documentation).toContain('@sensitive');
    expect(field.documentation).toContain('@encrypted');
  });
  it('门户访问原文令牌不入库，保留摘要且默认待启用', (): void => {
    const access = model('ClientAccess');
    expect(access.fields.find((field): boolean => field.name === 'tokenHash')?.documentation).toContain('@hashed');
    expect(access.fields.find((field): boolean => field.name === 'status')?.default).toBe('PENDING');
    expect(access.fields.some((field): boolean => field.name === 'token')).toBe(false);
  });
  it('数据库数值不使用 Float 保存金额或 RT', (): void => {
    for (const name of ['Case', 'RTWallet', 'RTTransaction', 'PriceConfig']) {
      expect(model(name).fields.some((field): boolean => field.type === 'Float')).toBe(false);
    }
  });
});
