import { Injectable } from '@nestjs/common';
import { PrismaRepository } from '../../prisma.repository';
import { BizException } from '../../biz-exception';
import { auditCase, lockCase } from './case-transaction';

@Injectable()
export class CaseDeleteService {
  constructor(private readonly repository: PrismaRepository) {}

  /** 同事务归档案件及关联可变数据，保留审计/访问日志；有法定期间记录时保守拒绝删除。 */
  async remove(userId: string, caseId: string): Promise<{ deleted: true }> {
    return this.repository.db.$transaction(async (tx): Promise<{ deleted: true }> => {
      await lockCase(tx, userId, caseId, true);
      if (await tx.task.count({ where: { caseId, deletedAt: null, source: 'DEADLINE_RULE' } })) {
        throw new BizException(40902, '案件包含法定期间记录，暂不允许删除；可将案件标记为已结案', 409);
      }
      if (await tx.ingestionRecord.count({ where: { matchedCaseId: caseId, deletedAt: null, userId: { not: userId } } })) {
        throw new BizException(40903, '案件包含其他用户的归集记录，请先处理协作归属', 409);
      }
      const now = new Date();
      const where = { caseId, deletedAt: null };
      const data = { deletedAt: now };
      const counts = {
        parties: (await tx.caseParty.updateMany({ where, data })).count,
        members: (await tx.caseMember.updateMany({ where, data: { ...data, status: 'REVOKED' } })).count,
        documents: (await tx.document.updateMany({ where, data })).count,
        tasks: (await tx.task.updateMany({ where, data })).count,
        timelineEvents: (await tx.timelineEvent.updateMany({ where, data })).count,
        analyses: (await tx.caseAnalysis.updateMany({ where, data })).count,
        drafts: (await tx.documentDraft.updateMany({ where, data })).count,
        ingestions: (await tx.ingestionRecord.updateMany({ where: { matchedCaseId: caseId, userId, deletedAt: null },
          data: { ...data, nextRetryAt: null } })).count,
        clientAccesses: (await tx.clientAccess.updateMany({ where,
          data: { ...data, status: 'REVOKED', revokedAt: now } })).count,
      };
      await tx.case.update({ where: { id: caseId }, data });
      await auditCase(tx, userId, caseId, 'CASE_DELETED', { counts });
      return { deleted: true };
    });
  }
}
