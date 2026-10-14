import { ForbiddenException, Injectable } from '@nestjs/common';
import { z } from 'zod';
import { PrismaRepository } from '../../prisma.repository';
import { OwnerOnlyPolicy } from './case-policy';

export interface ResourceParams { caseId?: string; documentId?: string; taskId?: string }
export interface AuthorizedScope { caseId: string; role: 'OWNER' }

/** 每次访问实时读取资源归属及协作状态；不存在与无权限统一返回 403。 */
@Injectable()
export class CaseAccessService {
  private readonly policy = new OwnerOnlyPolicy();
  constructor(private readonly repository: PrismaRepository) {}

  /** 解析所有路径资源，拒绝跨案件路径组合，禁止通过请求正文指定所有者。 */
  async authorize(userId: string, params: ResourceParams, method: string): Promise<AuthorizedScope> {
    const ids = Object.values(params).filter((value): value is string => value !== undefined);
    if (ids.length === 0 || ids.some((id): boolean => !z.string().uuid().safeParse(id).success)) {
      throw new ForbiddenException();
    }
    const caseIds: string[] = [];
    if (params.caseId) caseIds.push(params.caseId);
    if (params.documentId) {
      const document = await this.repository.db.document.findFirst({
        where: { id: params.documentId, deletedAt: null }, select: { caseId: true },
      });
      if (!document) throw new ForbiddenException();
      caseIds.push(document.caseId);
    }
    if (params.taskId) {
      const task = await this.repository.db.task.findFirst({
        where: { id: params.taskId, deletedAt: null }, select: { caseId: true },
      });
      if (!task) throw new ForbiddenException();
      caseIds.push(task.caseId);
    }
    if (new Set(caseIds).size !== 1) throw new ForbiddenException();
    const caseRecord = await this.repository.db.case.findFirst({
      where: { id: caseIds[0], deletedAt: null }, select: { id: true, ownerId: true,
        members: { where: { userId, status: 'ACCEPTED', deletedAt: null }, select: { role: true } } },
    });
    if (!caseRecord) throw new ForbiddenException();
    const role = caseRecord.ownerId === userId ? 'OWNER' : caseRecord.members[0]?.role;
    if (!this.policy.permits(role, method)) throw new ForbiddenException();
    return { caseId: caseRecord.id, role: 'OWNER' };
  }
}
