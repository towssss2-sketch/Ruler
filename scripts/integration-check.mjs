import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createConnection } from 'node:net';
import { createRequire } from 'node:module';

const require = createRequire(new URL('../backend/package.json', import.meta.url));
const { PrismaClient } = require('@prisma/client');
const { S3Client, CreateBucketCommand, PutObjectCommand, GetObjectCommand,
  DeleteObjectCommand, DeleteBucketCommand } = require('@aws-sdk/client-s3');
const prisma = new PrismaClient();
const bucket = `ruler-smoke-${randomUUID()}`;
const s3 = new S3Client({
  region: 'us-east-1', endpoint: process.env.MINIO_ENDPOINT, forcePathStyle: true,
  credentials: { accessKeyId: process.env.MINIO_ROOT_USER, secretAccessKey: process.env.MINIO_ROOT_PASSWORD },
});
let probe;
let bucketCreated = false;
try {
  probe = await prisma.environmentProbe.create({ data: { label: '虚构开发环境探针' } });
  const found = await prisma.environmentProbe.findUniqueOrThrow({ where: { id: probe.id } });
  assert.equal(found.label, '虚构开发环境探针');
  console.log('PASS PostgreSQL：Prisma 迁移后真实写入/读取');
  await new Promise((resolve, reject) => {
    const url = new URL(process.env.REDIS_URL);
    const socket = createConnection({ host: url.hostname, port: Number(url.port) });
    let reply = '';
    socket.setTimeout(5000, () => socket.destroy(new Error('Redis 检查超时')));
    socket.on('connect', () => socket.write('*1\r\n$4\r\nPING\r\n'));
    socket.on('data', (data) => {
      reply += data.toString();
      if (!reply.endsWith('\r\n')) return;
      socket.end();
      if (reply !== '+PONG\r\n') reject(new Error('Redis PING 响应错误'));
      else resolve();
    });
    socket.on('error', reject);
  });
  console.log('PASS Redis：真实 PING/PONG');
  const health = await fetch(`${process.env.MINIO_ENDPOINT}/minio/health/live`);
  assert.equal(health.status, 200);
  await s3.send(new CreateBucketCommand({ Bucket: bucket }));
  bucketCreated = true;
  await s3.send(new PutObjectCommand({ Bucket: bucket, Key: 'fictional.txt', Body: '虚构测试材料' }));
  const object = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: 'fictional.txt' }));
  assert.equal(await object.Body.transformToString(), '虚构测试材料');
  console.log('PASS MinIO：认证后 S3 上传/下载与内容校验');
} finally {
  if (probe) await prisma.environmentProbe.delete({ where: { id: probe.id } });
  await prisma.$disconnect();
  if (bucketCreated) {
    await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: 'fictional.txt' }));
    await s3.send(new DeleteBucketCommand({ Bucket: bucket }));
  }
  s3.destroy();
}
