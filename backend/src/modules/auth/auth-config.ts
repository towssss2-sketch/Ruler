import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test']),
  AUTH_SIGNING_KEY: z.string().regex(/^[a-f0-9]{64}$/),
  AUTH_CHALLENGE_KEY: z.string().regex(/^[a-f0-9]{64}$/),
  AUTH_REDIS_PREFIX: z.string().regex(/^ruler:[a-z0-9:-]{1,70}$/).default('ruler:auth:v1:'),
  REDIS_URL: z.string().url().refine((value): boolean => {
    try {
      const url = new URL(value);
      return url.protocol === 'redis:' && ['127.0.0.1', 'localhost'].includes(url.hostname);
    } catch { return false; }
  }),
});

export type AuthConfig = z.infer<typeof schema>;
export const AUTH_CONFIG = Symbol('AUTH_CONFIG');

/** 单独核验开发鉴权配置；错误只显示字段名，禁止输出值。 */
export function loadAuthConfig(environment: NodeJS.ProcessEnv): AuthConfig {
  const result = schema.safeParse(environment);
  if (!result.success) {
    throw new Error(`鉴权配置无效：${[...new Set(result.error.issues.map((issue): string => issue.path.join('.')))].join(', ')}`);
  }
  if (result.data.AUTH_SIGNING_KEY === result.data.AUTH_CHALLENGE_KEY) throw new Error('鉴权密钥必须分别生成');
  return result.data;
}
