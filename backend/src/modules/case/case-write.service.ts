import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { PrismaRepository } from '../../prisma.repository';
import { BizException } from '../../biz-exception';
import { CaseInput, CreateCaseInput } from './case-input';
import { CasePartiesService } from './case-parties.service';
import { CaseSummary, CaseViewService } from './case-view.service';
import { auditCase, lockCase } from './case-transaction';

@Injectable()
export class CaseWriteService {
  constructor(private readonly repository: PrismaRepository, private readonly parties: CasePartiesService,
    private readonly view: CaseViewService) {}

  /** 原子创建案件、当事人、有效 OWNER 与审计；同用户重复案号返回已有案件标识。 */
  async create(userId: string, input: CreateCaseInput): Promise<CaseSummary> {
    try {
      return await this.repository.db.$transaction(async (tx): Promise<CaseSummary> => {
        const id = randomUUID();
        const record = await tx.case.create({ data: { ...this.fields(input, id), id, ownerId: userId,
          caseNo: input.caseNo, court: input.court, cause: input.cause,
          members: { create: { userId, invitedBy: userId, role: 'OWNER', status: 'ACCEPTED', acceptedAt: new Date() } } } });
        await this.parties.sync(tx, id, input.parties);
        await auditCase(tx, userId, id, 'CASE_CREATED', { partyCount: input.parties.length });
        return this.view.summary(record);
      });
    } catch (error: unknown) { return this.duplicate(error, userId, input.caseNo, input.court); }
  }

  /** 锁定当前案件后更新，保留未提供字段；当事人列表按 id 同步，全部失败则回滚。 */
  async update(userId: string, caseId: string, input: CaseInput): Promise<CaseSummary> {
    let caseNo: string | undefined;
    let court: string | undefined;
    try {
      return await this.repository.db.$transaction(async (tx): Promise<CaseSummary> => {
        await lockCase(tx, userId, caseId, true);
        const current = await tx.case.findUniqueOrThrow({ where: { id: caseId } });
        caseNo = input.caseNo ?? current.caseNo;
        court = input.court ?? current.court;
        const record = await tx.case.update({ where: { id: caseId }, data: { ...this.fields(input, caseId), updatedAt: new Date() } });
        if (input.parties) await this.parties.sync(tx, caseId, input.parties);
        await auditCase(tx, userId, caseId, 'CASE_UPDATED', {
          fields: Object.entries(input).filter(([, value]): boolean => value !== undefined).map(([key]): string => key) });
        return this.view.summary(record);
      });
    } catch (error: unknown) { return this.duplicate(error, userId, caseNo, court); }
  }

  private fields(input: CaseInput, id: string): Partial<Prisma.CaseUncheckedCreateInput> {
    return { caseNo: input.caseNo, cause: input.cause, court: input.court, judge: input.judge, clerk: input.clerk,
      clerkPhone: this.parties.encrypt(input.clerkPhone, `Case:${id}:clerkPhone`),
      notes: this.parties.encrypt(input.notes, `Case:${id}:notes`), fee: input.fee, feeStatus: input.feeStatus,
      stage: input.stage, status: input.status };
  }

  private async duplicate(error: unknown, userId: string, caseNo?: string, court?: string): Promise<never> {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002' && caseNo && court) {
      const existing = await this.repository.db.case.findFirst({ where: { ownerId: userId, caseNo, court, deletedAt: null },
        select: { id: true } });
      if (existing) throw new BizException(40901, '该案号和法院的案件已存在，请打开已有案件', 409, { existingCaseId: existing.id });
    }
    throw error;
  }
}
