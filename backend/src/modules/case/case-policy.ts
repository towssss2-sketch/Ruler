import { MemberRole } from '@prisma/client';

/** 实时查库后调用的权限接口；本期只开放主办 OWNER，协作矩阵后续启用。 */
export interface CasePolicy {
  permits(role: MemberRole | undefined, method: string): boolean;
}

export class OwnerOnlyPolicy implements CasePolicy {
  /** 阶段 2 保守限制为 OWNER；协作成员不能因已有记录自动获得 API 权限。 */
  permits(role: MemberRole | undefined, _method: string): boolean {
    void _method;
    return role === 'OWNER';
  }
}
