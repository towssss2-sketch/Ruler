import { z } from 'zod';

export type RuntimeProfile = 'development' | 'restricted-local';
export const RUNTIME_PROFILE = Symbol('RUNTIME_PROFILE');
const profileSchema = z.enum(['development', 'restricted-local']).default('development');
const restrictedSchema = z.object({ NODE_ENV: z.enum(['development', 'test']),
  HOST: z.enum(['127.0.0.1', 'localhost']), RULER_TLS_CERT_FILE: z.string().min(1), RULER_TLS_KEY_FILE: z.string().min(1) });

/** 本机隔离模式必须显式启用并使用 TLS；材料有效性由应用工厂继续核验，错误不降级。 */
export function loadRuntimeProfile(environment: NodeJS.ProcessEnv): RuntimeProfile {
  const result = profileSchema.safeParse(environment.RULER_RUNTIME_PROFILE);
  if (!result.success || (result.data === 'restricted-local' && !restrictedSchema.safeParse(environment).success)) {
    throw new Error('运行模式配置无效');
  }
  return result.data;
}
