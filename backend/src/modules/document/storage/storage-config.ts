import { z } from 'zod';

const common = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']),
  STORAGE_DRIVER: z.enum(['minio', 'oss']),
  STORAGE_BUCKET: z.string().regex(/^[a-z][a-z0-9-]{1,61}[a-z0-9]$/),
  STORAGE_REGION: z.string().min(1).max(64),
  STORAGE_SIGNED_URL_TTL_SECONDS: z.coerce.number().int().min(1).max(600),
});
const local = z.object({ MINIO_ENDPOINT: z.string().url(), MINIO_SIGNING_ENDPOINT: z.string().url().optional(),
  MINIO_ROOT_USER: z.string().min(1), MINIO_ROOT_PASSWORD: z.string().min(8) });
const cloud = z.object({ OSS_ENDPOINT: z.string().url(), OSS_ACCESS_KEY_ID: z.string().min(1),
  OSS_ACCESS_KEY_SECRET: z.string().min(1), OSS_SECURITY_TOKEN: z.string().min(1).optional() });
interface SharedConfig { bucket: string; region: string; ttlSeconds: number; endpoint: string }
export interface MinioConfig extends SharedConfig { driver: 'minio'; signingEndpoint?: string; accessKeyId: string; secretAccessKey: string }
export interface OssConfig extends SharedConfig { driver: 'oss'; accessKeyId: string; accessKeySecret: string; securityToken?: string }
export type StorageConfig = MinioConfig | OssConfig;

/** 配置只从环境读取；开发 MinIO 只允许本机，OSS 只允许匹配区域的官方 HTTPS 端点，错误不包含值。 */
export function loadStorageConfig(environment: NodeJS.ProcessEnv): StorageConfig {
  const shared = common.safeParse(environment);
  if (!shared.success) throw new Error('文件存储配置无效');
  const c = shared.data;
  const base = { bucket: c.STORAGE_BUCKET, region: c.STORAGE_REGION, ttlSeconds: c.STORAGE_SIGNED_URL_TTL_SECONDS };
  if (c.STORAGE_DRIVER === 'minio') {
    const result = local.safeParse(environment);
    if (!result.success || c.NODE_ENV === 'production') throw new Error('开发存储配置无效');
    const d = result.data;
    const endpoint = checkedLocalOrigin(d.MINIO_ENDPOINT);
    const signingEndpoint = checkedLocalOrigin(d.MINIO_SIGNING_ENDPOINT ?? d.MINIO_ENDPOINT);
    return { ...base, driver: 'minio', endpoint, signingEndpoint,
      accessKeyId: d.MINIO_ROOT_USER, secretAccessKey: d.MINIO_ROOT_PASSWORD };
  }
  const result = cloud.safeParse(environment);
  if (!result.success || !/^oss-[a-z0-9-]+$/.test(base.region)) throw new Error('OSS 存储配置无效');
  const d = result.data;
  const url = checkedUrl(d.OSS_ENDPOINT);
  if (url.protocol !== 'https:' || url.hostname !== `${base.region}.aliyuncs.com` || url.port) throw new Error('OSS 存储端点无效');
  return { ...base, driver: 'oss', endpoint: url.origin, accessKeyId: d.OSS_ACCESS_KEY_ID,
    accessKeySecret: d.OSS_ACCESS_KEY_SECRET, securityToken: d.OSS_SECURITY_TOKEN };
}

/** 内部操作与签名入口同样只准本机；配置拆分不授权公网或生产存储。 */
function checkedLocalOrigin(value: string): string {
  const url = checkedUrl(value);
  if (!['http:', 'https:'].includes(url.protocol) || !['127.0.0.1', 'localhost'].includes(url.hostname)) throw new Error('开发存储端点无效');
  return url.origin;
}

/** 拒绝含用户信息、路径、查询或片段的端点，防止凭据或签名进入配置 URL。 */
function checkedUrl(value: string): URL {
  const url = new URL(value);
  if (url.username || url.password || url.search || url.hash || url.pathname !== '/') throw new Error('存储端点格式无效');
  return url;
}
