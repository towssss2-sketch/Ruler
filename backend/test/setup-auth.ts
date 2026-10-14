import { randomBytes } from 'node:crypto';

// 单测生成独立内存密钥，不使用真实账号或凭据，不连接外部邮件。
process.env.NODE_ENV = 'test';
process.env.AUTH_SIGNING_KEY ??= randomBytes(32).toString('hex');
process.env.AUTH_CHALLENGE_KEY ??= randomBytes(32).toString('hex');
process.env.FIELD_ENCRYPTION_KEY ??= randomBytes(32).toString('hex');
process.env.REDIS_URL ??= 'redis://127.0.0.1:6379';
