import { ForbiddenException, Injectable } from '@nestjs/common';
import { DocumentCategory, Prisma } from '@prisma/client';
import { PrismaRepository } from '../../../prisma.repository';
import { PreviewAttemptService } from './preview-attempt.service';

export interface SavedClassification {
  ruleVersion: string;
  category: DocumentCategory | null;
  reason: string;
  requiresConfirmation: true;
}
export interface PreviewClassificationView {
  attemptId: string;
  state: 'RECORDED' | 'NOT_RECORDED' | 'NOT_AVAILABLE';
  classification: SavedClassification | null;
}

/** 读取指定提取尝试的历史规则结果；不重新解析或按当前规则回填旧记录。 */
@Injectable()
export class PreviewClassificationService {
  constructor(private readonly repository: PrismaRepository, private readonly attempts: PreviewAttemptService) {}

  /** 同一快照实时检查本人未删除附件与账号；不存在/越权均拒绝，旧版成功记录明确返回未记录。 */
  async read(userId: string, ingestionId: string, attemptId: string): Promise<PreviewClassificationView> {
    return this.repository.db.$transaction(async (tx) => {
      await this.attempts.active(tx, userId, ingestionId);
      const row = await tx.ingestionPreviewAttempt.findFirst({ where: { id: attemptId, ingestionId, userId } });
      if (!row) throw new ForbiddenException();
      if (row.status !== 'SUCCEEDED') return { attemptId, state: 'NOT_AVAILABLE', classification: null };
      if (!row.classificationRuleVersion || !row.classificationReason) {
        return { attemptId, state: 'NOT_RECORDED', classification: null };
      }
      return { attemptId, state: 'RECORDED', classification: {
        ruleVersion: row.classificationRuleVersion, category: row.classificationCategory,
        reason: row.classificationReason, requiresConfirmation: true } };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead });
  }
}
