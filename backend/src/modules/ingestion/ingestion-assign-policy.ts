import { ForbiddenException } from '@nestjs/common';
import { Document, IngestionFile, IngestionRecord, Prisma } from '@prisma/client';
import { ApiProperty } from '@nestjs/swagger';
import { IsEnum, IsUUID } from 'class-validator';
import { DocumentCategory } from '@prisma/client';
import { BizException } from '../../biz-exception';
import { DocumentView, documentView } from '../document/document-policy';

export class AssignInput {
  @ApiProperty({ format: 'uuid' }) @IsUUID() caseId!: string;
  @ApiProperty({ enum: DocumentCategory }) @IsEnum(DocumentCategory) category!: DocumentCategory;
}
export type AssignRecord = IngestionRecord & { file: IngestionFile | null; documents: Document[] };

/** 所有写入在案件→用户锁之后读取归集记录；软删原件、他人材料不可归档。 */
export async function assignmentRecord(tx: Prisma.TransactionClient, userId: string, id: string): Promise<AssignRecord> {
  await tx.$queryRaw`SELECT id FROM "IngestionRecord" WHERE id = ${id}::uuid AND "userId" = ${userId}::uuid FOR UPDATE`;
  const row = await tx.ingestionRecord.findFirst({ where: { id, userId, deletedAt: null },
    include: { file: true, documents: true } });
  if (!row) throw new ForbiddenException();
  return row;
}

/** 同案件/分类的重复提交返回原文档；已删除、改派、忽略或无附件均不能隐式重建。 */
export function assignedDocument(row: AssignRecord, input: AssignInput): DocumentView | null {
  if (row.status === 'ASSIGNED' && row.matchedCaseId === input.caseId && row.documents.length === 1) {
    const document = row.documents[0]!;
    if (!document.deletedAt && document.category === input.category) return documentView(document);
  }
  if (row.status !== 'PENDING_MATCH' || row.matchedCaseId || row.documents.length) {
    throw new BizException(40922, '材料状态已改变，请刷新核对归档结果', 409);
  }
  if (!row.file) throw new BizException(40923, '此材料没有可归档附件，请先导入文件', 409);
  return null;
}
