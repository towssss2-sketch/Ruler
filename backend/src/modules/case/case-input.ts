import { BadRequestException } from '@nestjs/common';
import { CaseStage, CaseStatus, FeeStatus, PartyRole } from '@prisma/client';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsEnum, IsIn, IsOptional, IsString, IsUUID,
  Length, Matches, ValidateIf, validateSync } from 'class-validator';

/** 当事人输入；更新带 id 保留记录，不带 id 新增。联系方式可显式清空为 null。 */
export class PartyInput {
  @IsOptional() @IsUUID() id?: string;
  @IsEnum(PartyRole) role!: PartyRole;
  @IsString() @Length(1, 128) name!: string;
  @IsOptional() @IsString() @Length(1, 64) idCard?: string | null;
  @IsOptional() @IsString() @Length(1, 64) phone?: string | null;
  @IsOptional() @IsString() @Length(1, 1000) address?: string | null;
}

/** 案件创建/部分更新 DTO；金额用十进制字符串，避免浮点精度损失。 */
export class CaseInput {
  @ValidateIf((_, value: unknown): boolean => value !== undefined)
  @IsString() @Length(1, 80) @Matches(/^\([12]\d{3}\)[\p{Script=Han}\d]{1,60}号$/u) caseNo?: string;
  @ValidateIf((_, value: unknown): boolean => value !== undefined) @IsString() @Length(1, 128) cause?: string;
  @ValidateIf((_, value: unknown): boolean => value !== undefined) @IsString() @Length(1, 128) court?: string;
  @IsOptional() @IsString() @Length(1, 128) judge?: string | null;
  @IsOptional() @IsString() @Length(1, 128) clerk?: string | null;
  @IsOptional() @IsString() @Length(1, 64) clerkPhone?: string | null;
  @IsOptional() @IsString() @Length(1, 10000) notes?: string | null;
  @IsOptional() @IsString() @Matches(/^(0|[1-9]\d{0,11})(\.\d{1,2})?$/) fee?: string | null;
  @ValidateIf((_, value: unknown): boolean => value !== undefined) @IsEnum(FeeStatus) feeStatus?: FeeStatus;
  @ValidateIf((_, value: unknown): boolean => value !== undefined) @IsEnum(CaseStage) stage?: CaseStage;
  @ValidateIf((_, value: unknown): boolean => value !== undefined) @IsEnum(CaseStatus) status?: CaseStatus;
  @ValidateIf((_, value: unknown): boolean => value !== undefined)
  @IsArray() @ArrayMinSize(1) @ArrayMaxSize(100) parties?: PartyInput[];
}
export type CreateCaseInput = CaseInput & { caseNo: string; cause: string; court: string; parties: PartyInput[] };

/** 列表与冲突结果的有界分页；页码上限防止无界 OFFSET。 */
export class PageInput {
  @IsString() @Matches(/^[1-9]\d{0,3}$/) page = '1';
  @IsString() @Matches(/^([1-9]|[1-9]\d|100)$/) pageSize = '20';
}
export class CaseQuery extends PageInput {
  @ValidateIf((_, value: unknown): boolean => value !== undefined)
  @IsString() @Length(1, 80) @Matches(/^\([12]\d{3}\)[\p{Script=Han}\d]{1,60}号$/u) caseNo?: string;
  @IsOptional() @IsString() @Length(1, 128) keyword?: string;
  @IsOptional() @IsString() @Length(1, 128) court?: string;
  @IsOptional() @IsEnum(CaseStage) stage?: CaseStage;
  @IsOptional() @IsEnum(CaseStatus) status?: CaseStatus;
  @IsIn(['owned', 'collaborated']) group = 'owned';
  @IsIn(['asc', 'desc']) sort: 'asc' | 'desc' = 'desc';
}

/** 精确案号沿用建案的括号/空白归一化；不把非法值降级为全量列表。 */
export function caseQuery(input: unknown): CaseQuery {
  const raw = input && typeof input === 'object' && !Array.isArray(input) ? { ...input } : input;
  if (raw && typeof raw === 'object' && 'caseNo' in raw && typeof raw.caseNo === 'string') {
    raw.caseNo = raw.caseNo.replaceAll('（', '(').replaceAll('）', ')').replace(/\s/g, '');
  }
  return dto(CaseQuery, raw);
}

/** 校验普通 JSON 对象，拒绝未知字段/原型字段；错误不包含输入值。 */
export function dto<T extends object>(constructor: new () => T, input: unknown): T {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new BadRequestException();
  const result = new constructor();
  for (const [key, value] of Object.entries(input)) {
    if (['__proto__', 'constructor', 'prototype'].includes(key)) throw new BadRequestException();
    Object.defineProperty(result, key, { value: typeof value === 'string' ? value.trim() : value,
      enumerable: true, writable: true, configurable: true });
  }
  if (validateSync(result, { whitelist: true, forbidNonWhitelisted: true, forbidUnknownValues: true }).length) {
    throw new BadRequestException();
  }
  return result;
}

/** 中英文括号统一后校验；创建必须有案号、法院、案由和当事人。 */
export function caseInput(input: unknown, create: true): CreateCaseInput;
export function caseInput(input: unknown, create: false): CaseInput;
export function caseInput(input: unknown, create: boolean): CaseInput {
  const raw = input && typeof input === 'object' && !Array.isArray(input) ? { ...input } : input;
  if (raw && typeof raw === 'object' && 'caseNo' in raw && typeof raw.caseNo === 'string') {
    raw.caseNo = raw.caseNo.replaceAll('（', '(').replaceAll('）', ')').replace(/\s/g, '');
  }
  const result = dto(CaseInput, raw);
  if (Object.values(result).every((value: unknown): boolean => value === undefined)) throw new BadRequestException();
  if (create && (!result.caseNo || !result.court || !result.cause || !result.parties)) throw new BadRequestException();
  if (result.parties) {
    result.parties = result.parties.map((party): PartyInput => dto(PartyInput, party));
    const ids = result.parties.flatMap((party): string[] => party.id ? [party.id] : []);
    if (new Set(ids).size !== ids.length || (create && ids.length > 0)) throw new BadRequestException();
    if (result.parties.some((party): boolean => party.id === null)) throw new BadRequestException();
  }
  return result;
}
