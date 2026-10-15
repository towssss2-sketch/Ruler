import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { MinioConfig, OssConfig } from '../../src/modules/document/storage/storage-config';
import { storageKey } from '../../src/modules/document/storage/storage-policy';
import { UploadRequest } from '../../src/modules/document/storage/storage.service';

export const fictionalContent = Buffer.from('%PDF-1.7\n仅为虚构存储测试，不含真实案情\n');

/** 生成内存虚构对象名与校验值，不能输出签名或凭据。 */
export function uploadInput(name = '虚构材料.pdf'): UploadRequest {
  return { key: storageKey(randomUUID(), randomUUID(), randomUUID(), 1, name), mimeType: 'application/pdf',
    sizeBytes: fictionalContent.length, contentMd5: createHash('md5').update(fictionalContent).digest('base64') };
}

/** 离线 SDK 测试使用随机无效凭据，绝不访问真实云账号。 */
export function minioConfig(): MinioConfig {
  return { driver: 'minio', endpoint: 'http://127.0.0.1:9000', bucket: 'fictional-storage-test',
    region: 'us-east-1', ttlSeconds: 600, accessKeyId: randomBytes(12).toString('hex'), secretAccessKey: randomBytes(32).toString('hex') };
}

/** OSS 的签名计算离线进行；以下域名仅参与 URL 生成，不进行网络请求。 */
export function ossConfig(): OssConfig {
  return { driver: 'oss', endpoint: 'https://oss-cn-hangzhou.aliyuncs.com', bucket: 'fictional-storage-test',
    region: 'oss-cn-hangzhou', ttlSeconds: 600, accessKeyId: randomBytes(12).toString('hex'),
    accessKeySecret: randomBytes(32).toString('hex'), securityToken: randomBytes(32).toString('hex') };
}
