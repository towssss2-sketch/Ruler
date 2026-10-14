import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { EncryptionService } from '../../encryption.service';
import { PartyInput } from './case-input';

@Injectable()
export class CasePartiesService {
  constructor(private readonly cipher: EncryptionService) {}

  /** 返回加密写入数据；未提供字段保留，null 明确清空，AAD 绑定记录和字段。 */
  data(input: PartyInput, id: string): Prisma.CasePartyUpdateManyMutationInput {
    return { role: input.role, name: input.name,
      idCard: this.encrypt(input.idCard, `CaseParty:${id}:idCard`),
      phone: this.encrypt(input.phone, `CaseParty:${id}:phone`),
      address: this.encrypt(input.address, `CaseParty:${id}:address`) };
  }

  /** 加密可选字段；不打印明文，未提供时交给 Prisma 保留原值。 */
  encrypt(value: string | null | undefined, context: string): Uint8Array<ArrayBuffer> | null | undefined {
    return value === undefined || value === null ? value : this.cipher.encrypt(value, context);
  }

  /** 同事务同步当事人；拒绝外案或已删除 id，移除时吊销预留门户权限。 */
  async sync(tx: Prisma.TransactionClient, caseId: string, parties: PartyInput[]): Promise<void> {
    const current = await tx.caseParty.findMany({ where: { caseId, deletedAt: null }, select: { id: true } });
    const ids = new Set(current.map((party): string => party.id));
    const kept = parties.flatMap((party): string[] => party.id ? [party.id] : []);
    if (kept.some((id): boolean => !ids.has(id))) throw new BadRequestException();
    const removed = current.filter((party): boolean => !kept.includes(party.id)).map((party): string => party.id);
    const now = new Date();
    await tx.clientAccess.updateMany({ where: { caseId, casePartyId: { in: removed }, deletedAt: null },
      data: { status: 'REVOKED', revokedAt: now, deletedAt: now } });
    await tx.caseParty.updateMany({ where: { caseId, id: { in: removed }, deletedAt: null }, data: { deletedAt: now } });
    for (const party of parties) {
      const id = party.id ?? randomUUID();
      if (party.id) await tx.caseParty.update({ where: { id }, data: this.data(party, id) });
      else await tx.caseParty.create({ data: { id, caseId, role: party.role, name: party.name,
        idCard: this.encrypt(party.idCard, `CaseParty:${id}:idCard`),
        phone: this.encrypt(party.phone, `CaseParty:${id}:phone`),
        address: this.encrypt(party.address, `CaseParty:${id}:address`) } });
    }
  }
}
