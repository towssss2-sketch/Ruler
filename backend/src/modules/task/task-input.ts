import { BadRequestException } from '@nestjs/common';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { TaskSource, TaskStatus } from '@prisma/client';
import { IsBoolean, IsEnum, IsString, Length, ValidateIf } from 'class-validator';
import { dto, PageInput } from '../case/case-input';

/** 手动任务输入，不接受 source、确认信息或客户端指定完成时间。 */
export class TaskInput {
  @ApiPropertyOptional({ description: '任务标题，创建时必填' })
  @ValidateIf((_, value: unknown): boolean => value !== undefined) @IsString() @Length(1, 255) title?: string;
  @ApiPropertyOptional({ nullable: true, description: '描述，落库加密；null 清空' })
  @ValidateIf((_, value: unknown): boolean => value !== undefined && value !== null)
  @IsString() @Length(1, 10000) description?: string | null;
  @ApiPropertyOptional({ nullable: true, description: 'YYYY-MM-DD；普通工作日期，不代表法定期限' })
  @ValidateIf((_, value: unknown): boolean => value !== undefined && value !== null) @IsString() dueDate?: string | null;
  @ApiPropertyOptional({ enum: TaskStatus })
  @ValidateIf((_, value: unknown): boolean => value !== undefined) @IsEnum(TaskStatus) status?: TaskStatus;
  @ApiPropertyOptional()
  @ValidateIf((_, value: unknown): boolean => value !== undefined) @IsBoolean() isClientVisible?: boolean;
}
export class TaskQuery extends PageInput {
  @ValidateIf((_, value: unknown): boolean => value !== undefined) @IsEnum(TaskSource) source?: TaskSource;
  @ValidateIf((_, value: unknown): boolean => value !== undefined) @IsEnum(TaskStatus) status?: TaskStatus;
}

/** 严格日历日期，拒绝自动滚动的无效日期和时区/时间片段。 */
export function calendarDate(input: string): Date {
  if (!/^[1-9]\d{3}-\d{2}-\d{2}$/.test(input)) throw new BadRequestException();
  const date = new Date(`${input}T00:00:00.000Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== input) throw new BadRequestException();
  return date;
}

/** 创建标题必填，更新必须有字段；日期和未知字段均严格验证。 */
export function taskInput(input: unknown, create: boolean): TaskInput {
  const result = dto(TaskInput, input);
  if ((create && !result.title) || Object.values(result).every((value: unknown): boolean => value === undefined)) {
    throw new BadRequestException();
  }
  if (typeof result.dueDate === 'string') calendarDate(result.dueDate);
  return result;
}
