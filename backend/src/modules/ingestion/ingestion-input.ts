import { BadRequestException } from '@nestjs/common';
import { IsString, Length } from 'class-validator';
import { dto } from '../case/case-input';

/** 手动转发微信文字；文件、来源、归属、AI 结果均不能由调用者伪造。 */
export class TextIngestionInput {
  @IsString() @Length(1, 10000) rawContent!: string;
}

/** 统一换行和首尾空白以稳定重试判重，保留正文内部空白及大小写。 */
export function textIngestionInput(input: unknown): TextIngestionInput {
  const result = dto(TextIngestionInput, input);
  if (result.rawContent.includes('\0')) throw new BadRequestException();
  result.rawContent = result.rawContent.replace(/\r\n?/g, '\n');
  return result;
}

/** 状态动作不接受额外的归属或处理结果字段。 */
export function emptyIngestionInput(input: unknown): void {
  if (!input || typeof input !== 'object' || Array.isArray(input) || Object.keys(input).length !== 0) {
    throw new BadRequestException();
  }
}
