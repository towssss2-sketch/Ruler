import { Injectable } from '@nestjs/common';
import { PrismaRepository } from '../../prisma.repository';
import { PageInput } from './case-input';
import { auditCase, lockCase } from './case-transaction';

interface ConflictMatch { caseId: string; caseNo: string; court: string; deleted: boolean; similarity: number }
export interface ConflictPage { items: ConflictMatch[]; total: number; page: number; pageSize: number; threshold: 0.6 }

@Injectable()
export class CaseConflictService {
  constructor(private readonly repository: PrismaRepository) {}

  /** 使用参数化 pg_trgm 查询本人历史案件（含软删案件/当事人），只提供候选提示，不作法律结论。 */
  async check(userId: string, caseId: string, query: PageInput): Promise<ConflictPage> {
    return this.repository.db.$transaction(async (tx): Promise<ConflictPage> => {
      await lockCase(tx, userId, caseId, false);
      const page = Number(query.page);
      const pageSize = Number(query.pageSize);
      // 先按案件聚合，避免同名多人造成重复案件；完整总数不受越界分页影响。
      const rows = await tx.$queryRaw<{ items: ConflictMatch[]; total: number }[]>`
        WITH matches AS (
          SELECT c.id AS "caseId", c."caseNo", c.court, (c."deletedAt" IS NOT NULL) AS deleted,
            max(public.similarity(p.name, source.name)) AS similarity
          FROM "Case" c JOIN "CaseParty" p ON p."caseId" = c.id
          JOIN "CaseParty" source ON source."caseId" = ${caseId}::uuid AND source."deletedAt" IS NULL
          WHERE c."ownerId" = ${userId}::uuid AND c.id <> ${caseId}::uuid
            AND public.similarity(p.name, source.name) >= 0.6
          GROUP BY c.id
        ), selected AS (
          SELECT * FROM matches ORDER BY similarity DESC, "caseId" ASC
          LIMIT ${pageSize} OFFSET ${(page - 1) * pageSize}
        ) SELECT (SELECT count(*)::int FROM matches) AS total,
          coalesce((SELECT json_agg(selected ORDER BY similarity DESC, "caseId" ASC) FROM selected), '[]'::json) AS items`;
      const result = rows[0]!;
      await auditCase(tx, userId, caseId, 'CASE_CONFLICT_CHECKED', { matchCount: result.total });
      return { ...result, page, pageSize, threshold: 0.6 };
    });
  }
}
