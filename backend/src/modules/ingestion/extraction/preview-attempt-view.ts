import { IngestionPreviewAttempt } from '@prisma/client';

export type PreviewAttemptView = Pick<IngestionPreviewAttempt, 'id' | 'status' | 'reason' | 'startedAt' | 'finishedAt'> & {
  retryable: boolean;
};
export interface PreviewAttemptPage { items: PreviewAttemptView[]; total: number; page: number; pageSize: number }

/** 超时运行记录立即呈现中断；GET 不写库，新尝试开始时再原子固化中断及审计。 */
export function previewAttemptView(row: IngestionPreviewAttempt, now: Date): PreviewAttemptView {
  const expired = row.status === 'RUNNING' && row.leaseExpiresAt <= now;
  const status = expired ? 'INTERRUPTED' : row.status;
  return { id: row.id, status, reason: row.reason, startedAt: row.startedAt,
    finishedAt: expired ? row.leaseExpiresAt : row.finishedAt,
    retryable: status === 'INTERRUPTED' || (status === 'MANUAL_REQUIRED' && ['TIMEOUT', 'UNAVAILABLE'].includes(row.reason!)) };
}
