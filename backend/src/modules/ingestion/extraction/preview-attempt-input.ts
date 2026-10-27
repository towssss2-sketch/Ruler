import { BadRequestException } from '@nestjs/common';
import { dto, PageInput } from '../../case/case-input';

/** 检查原始查询参数，避免框架丢弃原型字段或把重复参数静默折叠。 */
export function previewAttemptQuery(originalUrl: string): PageInput {
  const query = Object.create(null) as Record<string, string>;
  for (const [key, value] of new URL(originalUrl, 'http://localhost').searchParams) {
    if (!['page', 'pageSize'].includes(key) || Object.hasOwn(query, key)) throw new BadRequestException();
    query[key] = value;
  }
  return dto(PageInput, query);
}
