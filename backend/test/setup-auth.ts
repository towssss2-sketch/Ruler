import { randomBytes } from 'node:crypto';

// 单测生成独立内存密钥，不使用真实账号或凭据，不连接外部邮件。
process.env.NODE_ENV = 'test';
process.env.AUTH_SIGNING_KEY ??= randomBytes(32).toString('hex');
process.env.AUTH_CHALLENGE_KEY ??= randomBytes(32).toString('hex');
process.env.FIELD_ENCRYPTION_KEY ??= randomBytes(32).toString('hex');
process.env.REDIS_URL ??= 'redis://127.0.0.1:6379';
process.env.STORAGE_DRIVER ??= 'minio';
process.env.STORAGE_BUCKET ??= 'ruler-unit-tests';
process.env.STORAGE_REGION ??= 'us-east-1';
process.env.STORAGE_SIGNED_URL_TTL_SECONDS ??= '600';
process.env.MINIO_ENDPOINT ??= 'http://127.0.0.1:9000';
process.env.MINIO_ROOT_USER ??= randomBytes(12).toString('hex');
process.env.MINIO_ROOT_PASSWORD ??= randomBytes(32).toString('hex');
