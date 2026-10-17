import { createRequire } from 'node:module';
const require = createRequire(new URL('../backend/package.json', import.meta.url));
const { S3Client, CreateBucketCommand, ListObjectsV2Command, DeleteObjectsCommand,
  DeleteBucketCommand } = require('@aws-sdk/client-s3');

/** 只创建并清理本次随机测试桶，不复用应用桶，不修改桶策略。 */
export async function clientStorageFixture(id) {
  if (!/^[a-f0-9]{32}$/.test(id)) throw new Error('测试桶标识无效');
  let endpoint;
  try { endpoint = new URL(process.env.MINIO_ENDPOINT); } catch { throw new Error('测试存储配置无效'); }
  if (!['localhost', '127.0.0.1'].includes(endpoint.hostname)) throw new Error('测试存储必须为本机');
  const bucket = `ruler-client-${id}`;
  const client = new S3Client({ endpoint: endpoint.origin, region: process.env.STORAGE_REGION,
    forcePathStyle: true, credentials: { accessKeyId: process.env.MINIO_ROOT_USER,
      secretAccessKey: process.env.MINIO_ROOT_PASSWORD } });
  try { await client.send(new CreateBucketCommand({ Bucket: bucket })); }
  catch { client.destroy(); throw new Error('无法创建本次隔离测试桶'); }
  process.env.STORAGE_BUCKET = bucket;
  process.env.STORAGE_DRIVER = 'minio';
  return { origin: endpoint.origin, async close() {
    try {
      for (;;) {
        const result = await client.send(new ListObjectsV2Command({ Bucket: bucket, MaxKeys: 1000 }));
        if (!result.Contents?.length) break;
        const deleted = await client.send(new DeleteObjectsCommand({ Bucket: bucket,
          Delete: { Objects: result.Contents.map(item => ({ Key: item.Key })) } }));
        if (deleted.Errors?.length) throw new Error('测试对象清理失败');
      }
      await client.send(new DeleteBucketCommand({ Bucket: bucket }));
    } catch { throw new Error('本次隔离测试桶未完整清理'); }
    finally { client.destroy(); }
  } };
}
