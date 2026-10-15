import { createRequire } from 'node:module';

const require = createRequire(new URL('../backend/package.json', import.meta.url));
const { loadStorageConfig } = require('./dist/modules/document/storage/storage-config');
const { S3Client, HeadBucketCommand, CreateBucketCommand, GetBucketPolicyCommand } = require('@aws-sdk/client-s3');
let client;
try {
  const config = loadStorageConfig(process.env);
  if (!['development', 'test'].includes(process.env.NODE_ENV) || config.driver !== 'minio') throw new Error();
  client = new S3Client({ endpoint: config.endpoint, region: config.region, forcePathStyle: true,
    credentials: { accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey } });
  try { await client.send(new HeadBucketCommand({ Bucket: config.bucket })); }
  catch (error) {
    if (error?.$metadata?.httpStatusCode !== 404) throw error;
    await client.send(new CreateBucketCommand({ Bucket: config.bucket }));
  }
  // 默认新桶私有；拒绝带既有策略的开发桶，不擅自重写其策略或删除任何对象。
  try { await client.send(new GetBucketPolicyCommand({ Bucket: config.bucket })); throw new Error(); }
  catch (error) { if (error?.name !== 'NoSuchBucketPolicy') throw error; }
  console.log('PASS 本机私有开发桶就绪；未连接 OSS、未修改既有策略或对象');
} catch {
  console.error('FAIL 开发桶初始化失败；检查开发配置、本机 MinIO 与桶策略（凭据已隐藏）');
  process.exitCode = 1;
} finally { client?.destroy(); }
