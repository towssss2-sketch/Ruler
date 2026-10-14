import { applyDecorators } from '@nestjs/common';
import { ApiQuery } from '@nestjs/swagger';
import { SchemaObject } from '@nestjs/swagger/dist/interfaces/open-api-spec.interface';
import { CaseStage, CaseStatus, FeeStatus, PartyRole } from '@prisma/client';

export const CASE_BODY: SchemaObject = { type: 'object', additionalProperties: false, properties: {
  caseNo: { type: 'string', maxLength: 80, example: '(2026)浙0302民初16812号' },
  cause: { type: 'string', maxLength: 128, description: '仅填写虚构案由' },
  court: { type: 'string', maxLength: 128, description: '仅填写虚构法院' },
  judge: { type: 'string', nullable: true }, clerk: { type: 'string', nullable: true },
  clerkPhone: { type: 'string', nullable: true, description: '落库加密；仅用虚构文本' },
  notes: { type: 'string', nullable: true, maxLength: 10000, description: '落库加密' },
  fee: { type: 'string', nullable: true, pattern: '^(0|[1-9]\\d{0,11})(\\.\\d{1,2})?$', description: '精确十进制字符串' },
  feeStatus: { type: 'string', enum: Object.values(FeeStatus) }, stage: { type: 'string', enum: Object.values(CaseStage) },
  status: { type: 'string', enum: Object.values(CaseStatus) },
  parties: { type: 'array', minItems: 1, maxItems: 100, description: 'PATCH 时提供完整列表；省略的当事人软删除',
    items: { type: 'object', additionalProperties: false, required: ['role', 'name'], properties: {
      id: { type: 'string', format: 'uuid', description: '只用于更新已有当事人；创建时禁止提供' },
      role: { type: 'string', enum: Object.values(PartyRole) }, name: { type: 'string', maxLength: 128 },
      idCard: { type: 'string', nullable: true }, phone: { type: 'string', nullable: true },
      address: { type: 'string', nullable: true },
    } } },
} };

/** 公开分页限制，与 DTO 的页码及页大小约束一致。 */
export function casePageQueries(): MethodDecorator {
  return applyDecorators(ApiQuery({ name: 'page', required: false, schema: { type: 'integer', minimum: 1, maximum: 9999, default: 1 } }),
    ApiQuery({ name: 'pageSize', required: false, schema: { type: 'integer', minimum: 1, maximum: 100, default: 20 } }));
}

/** 公开列表筛选参数，协作组仅预留；没有可指定 ownerId 的参数。 */
export function caseListQueries(): MethodDecorator {
  return applyDecorators(casePageQueries(),
    ...['keyword', 'court'].map((name): MethodDecorator => ApiQuery({ name, required: false, type: String })),
    ApiQuery({ name: 'stage', required: false, enum: CaseStage }), ApiQuery({ name: 'status', required: false, enum: CaseStatus }),
    ApiQuery({ name: 'sort', required: false, enum: ['asc', 'desc'] }),
    ApiQuery({ name: 'group', required: false, enum: ['owned', 'collaborated'] }));
}
