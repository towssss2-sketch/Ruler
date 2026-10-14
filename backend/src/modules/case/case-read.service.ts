import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaRepository } from '../../prisma.repository';
import { CaseQuery } from './case-input';
import { CaseDetail, CaseSummary, CaseViewService } from './case-view.service';
import { lockCase } from './case-transaction';

export interface CasePage { items: CaseSummary[]; total: number; page: number; pageSize: number;
  group: string; collaborationEnabled: false }

@Injectable()
export class CaseReadService {
  constructor(private readonly repository: PrismaRepository, private readonly view: CaseViewService) {}

  /** 仅检索本人活跃主办案件，稳定排序；协作组明确预留为空，阶段 9 开启。 */
  async list(userId: string, query: CaseQuery): Promise<CasePage> {
    const page = Number(query.page);
    const pageSize = Number(query.pageSize);
    const base = { page, pageSize, group: query.group, collaborationEnabled: false as const };
    if (query.group === 'collaborated') return { ...base, items: [], total: 0 };
    const keyword = query.keyword;
    const where: Prisma.CaseWhereInput = { ownerId: userId, deletedAt: null, court: query.court,
      stage: query.stage, status: query.status, ...(keyword ? { OR: [
        { caseNo: { contains: keyword.replaceAll('（', '(').replaceAll('）', ')') } },
        { cause: { contains: keyword } },
        { parties: { some: { deletedAt: null, name: { contains: keyword } } } },
      ] } : {}) };
    return this.repository.db.$transaction(async (tx): Promise<CasePage> => {
      const total = await tx.case.count({ where });
      const records = await tx.case.findMany({ where, skip: (page - 1) * pageSize, take: pageSize,
        orderBy: [{ updatedAt: query.sort }, { id: query.sort }],
        select: { id: true, caseNo: true, cause: true, court: true, stage: true, status: true, updatedAt: true } });
      return { ...base, total, items: records.map((record): CaseSummary => this.view.summary(record)) };
    }, { isolationLevel: 'RepeatableRead' });
  }

  /** 授权后解密当事人与案件详情，统计当前文件版本及未完成任务，排除软删除记录。 */
  async detail(userId: string, caseId: string): Promise<CaseDetail> {
    return this.repository.db.$transaction(async (tx): Promise<CaseDetail> => {
      await lockCase(tx, userId, caseId, false);
      const record = await tx.case.findUniqueOrThrow({ where: { id: caseId },
        include: { parties: { where: { deletedAt: null }, orderBy: [{ createdAt: 'asc' }, { id: 'asc' }] } } });
      const documents = await tx.document.count({ where: { caseId, deletedAt: null, isCurrentVersion: true } });
      const tasks = await tx.task.count({ where: { caseId, deletedAt: null, status: 'TODO' } });
      return this.view.detail(record, documents, tasks);
    });
  }
}
