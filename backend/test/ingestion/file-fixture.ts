import { createHash } from 'node:crypto';
import { request } from '../auth/fixture';
import { content, uploadInput } from '../document/fixture';
import { storageFetch } from '../storage/minio-fixture';
import { IngestionOffer } from '../../src/modules/ingestion/ingestion-file-upload.service';

/** 真正向本次隔离 MinIO 桶直传虚构字节，签名不输出到断言。 */
export async function fileOffer(access: string, name = '虚构待定.pdf', bytes: Buffer = content): Promise<IngestionOffer> {
  const result = await request('/ingestion/files/presign', uploadInput({ fileName: name, sizeBytes: bytes.length,
    contentMd5: createHash('md5').update(bytes).digest('base64') }), access);
  expect(result.status).toBe(201);
  const signed = result.data as unknown as IngestionOffer;
  const upload = await storageFetch(signed.url, { method: 'PUT', headers: signed.headers, body: Uint8Array.from(bytes) });
  expect(upload.status).toBe(200); await upload.arrayBuffer(); return signed;
}

/** 只提供票据 ID，不允许客户端声明内容指纹或正式对象路径。 */
export function complete(access: string, uploadId: string): ReturnType<typeof request> {
  return request('/ingestion/files', { uploadId }, access);
}
