import { z } from 'zod';
import { EncryptionService } from './encryption.service';

/** 读取独立字段密钥；缺失、复用鉴权密钥或生产环境均拒绝启动，不输出值。 */
export function configuredCipher(environment: NodeJS.ProcessEnv): EncryptionService {
  const parsed = z.object({ NODE_ENV: z.enum(['development', 'test']),
    FIELD_ENCRYPTION_KEY: z.string().regex(/^[a-f0-9]{64}$/) }).safeParse(environment);
  if (!parsed.success) throw new Error('字段加密配置无效');
  const key = parsed.data.FIELD_ENCRYPTION_KEY;
  if ([environment.AUTH_SIGNING_KEY, environment.AUTH_CHALLENGE_KEY].includes(key)) {
    throw new Error('字段加密密钥必须独立生成');
  }
  return new EncryptionService(Buffer.from(key, 'hex'));
}
