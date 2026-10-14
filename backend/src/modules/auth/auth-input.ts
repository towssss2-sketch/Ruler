import { BadRequestException } from '@nestjs/common';
import { z } from 'zod';

export const emailInput = z.string().trim().toLowerCase().email().max(254);
const passwordInput = z.string().min(12).max(128)
  .refine((value): boolean => Buffer.byteLength(value, 'utf8') <= 512);
export const requestCodeInput = z.object({ email: emailInput }).strict();
export const registerInput = z.object({
  email: emailInput, code: z.string().regex(/^\d{6}$/), password: passwordInput,
  name: z.string().trim().min(1).max(128),
}).strict();
export const loginInput = z.object({ email: emailInput, password: passwordInput }).strict();
export const refreshInput = z.object({ refreshToken: z.string().min(43).max(256) }).strict();

/** 校验未知 HTTP 正文；只返回固定中文错误，不回显输入。 */
export function parseInput<T>(schema: z.ZodType<T>, input: unknown): T {
  const parsed = schema.safeParse(input);
  if (!parsed.success) throw new BadRequestException('输入格式不正确');
  return parsed.data;
}
