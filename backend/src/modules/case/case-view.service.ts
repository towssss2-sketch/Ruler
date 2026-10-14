import { Injectable } from '@nestjs/common';
import { Case, CaseParty } from '@prisma/client';
import { EncryptionService } from '../../encryption.service';

export type CaseSummary = Pick<Case, 'id' | 'caseNo' | 'cause' | 'court' | 'stage' | 'status' | 'updatedAt'>;
export type PartyView = Pick<CaseParty, 'id' | 'role' | 'name'> & {
  idCard: string | null; phone: string | null; address: string | null;
};
export type CaseDetail = CaseSummary & { judge: string | null; clerk: string | null; clerkPhone: string | null;
  notes: string | null; fee: string | null; feeStatus: Case['feeStatus']; createdAt: Date;
  parties: PartyView[]; documentCount: number; pendingTaskCount: number };

@Injectable()
export class CaseViewService {
  constructor(private readonly cipher: EncryptionService) {}

  /** 明确选择列表字段，避免密文、联系人和案情备注出现在列表中。 */
  summary(record: CaseSummary): CaseSummary {
    const { id, caseNo, cause, court, stage, status, updatedAt } = record;
    return { id, caseNo, cause, court, stage, status, updatedAt };
  }

  /** 仅在授权事务内解密详情；损坏密文抛固定错误，不回传部分数据。 */
  detail(record: Case & { parties: CaseParty[] }, documentCount: number, pendingTaskCount: number): CaseDetail {
    return { ...this.summary(record), judge: record.judge, clerk: record.clerk,
      clerkPhone: this.read(record.clerkPhone, `Case:${record.id}:clerkPhone`),
      notes: this.read(record.notes, `Case:${record.id}:notes`), fee: record.fee?.toFixed(2) ?? null,
      feeStatus: record.feeStatus, createdAt: record.createdAt, documentCount, pendingTaskCount,
      parties: record.parties.map((party): PartyView => ({ id: party.id, role: party.role, name: party.name,
        idCard: this.read(party.idCard, `CaseParty:${party.id}:idCard`),
        phone: this.read(party.phone, `CaseParty:${party.id}:phone`),
        address: this.read(party.address, `CaseParty:${party.id}:address`) })) };
  }

  private read(value: Uint8Array | null, context: string): string | null {
    return value === null ? null : this.cipher.decrypt(value, context);
  }
}
