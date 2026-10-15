import { Prisma } from '@prisma/client';
import { client } from './fixtures';

afterAll(async (): Promise<void> => { await client.$disconnect(); });

describe('迁移后的实际数据库结构', (): void => {
  it('全部业务、鉴权、上传票据及探针表均实际存在，列名与 Prisma 一致', async (): Promise<void> => {
    const rows = await client.$queryRaw<Array<{ table_name: string; column_name: string; udt_name: string }>>`
      SELECT table_name, column_name, udt_name FROM information_schema.columns
      WHERE table_schema = current_schema()
    `;
    for (const model of Prisma.dmmf.datamodel.models) {
      const fields = model.fields.filter((field): boolean => field.kind !== 'object');
      const table = rows.filter((row): boolean => row.table_name === model.name);
      expect(table.map((row): string => row.column_name).sort()).toEqual(fields.map((field): string => field.name).sort());
      expect(table.find((row): boolean => row.column_name === 'id')?.udt_name).toBe('uuid');
      for (const field of fields.filter((field): boolean => field.type === 'Bytes')) {
        expect(table.find((row): boolean => row.column_name === field.name)?.udt_name).toBe('bytea');
      }
    }
  });
  it.each([
    'CaseMember_userId_status_idx', 'IngestionRecord_userId_status_receivedAt_idx',
    'Task_caseId_dueDate_status_idx', 'Document_caseId_category_idx',
    'Case_active_identity', 'Document_one_current_version',
  ])('所需索引 %s 已实际建立', async (name: string): Promise<void> => {
    const rows = await client.$queryRaw<Array<{ indexname: string }>>`
      SELECT indexname FROM pg_indexes WHERE schemaname=current_schema() AND indexname=${name}
    `;
    expect(rows).toHaveLength(1);
  });
  it('pg_trgm 可用于后续虚构姓名冲突检查', async (): Promise<void> => {
    const rows = await client.$queryRaw<Array<{ similarity: number }>>`
      SELECT public.similarity('虚构当事人甲', '虚构当事人甲') AS similarity
    `;
    expect(rows[0]?.similarity).toBe(1);
  });
});
