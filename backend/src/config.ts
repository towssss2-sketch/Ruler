import { z } from 'zod';

const configSchema = z.object({
  NODE_ENV: z.enum(['development', 'test']).default('development'),
  HOST: z.string().min(1),
  PORT: z.coerce.number().int().min(1).max(65535),
  DATABASE_URL: z.string().url().refine(
    (value: string): boolean => value.startsWith('postgresql://'),
  ),
});

export type AppConfig = z.infer<typeof configSchema>;

/** 验证环境变量；错误只显示字段名称，禁止输出连接串或凭据。 */
export function loadConfig(environment: NodeJS.ProcessEnv): AppConfig {
  const result = configSchema.safeParse(environment);
  if (!result.success) {
    const fields = [...new Set(result.error.issues.map((issue): string => issue.path.join('.')))];
    throw new Error(`环境配置无效：${fields.join(', ')}`);
  }
  return result.data;
}
