import { createRequire } from 'node:module';
const require = createRequire(new URL('../backend/package.json', import.meta.url));

/** 用编译后的真实驱动离线签名；不用 .env 或真实凭据，不发网络请求、不输出签名。 */
export async function probeCurrentStorage() {
  const { loadStorageConfig } = require('../backend/dist/modules/document/storage/storage-config.js');
  const { S3Driver } = require('../backend/dist/modules/document/storage/s3-driver.js');
  const fixture = { NODE_ENV: 'test', STORAGE_DRIVER: 'minio', STORAGE_BUCKET: 'fictional-preview-probe',
    STORAGE_REGION: 'us-east-1', STORAGE_SIGNED_URL_TTL_SECONDS: '60',
    MINIO_ROOT_USER: 'fictional-offline-probe', MINIO_ROOT_PASSWORD: 'fictional-offline-probe-only',
    MINIO_ENDPOINT: 'http://127.0.0.1:9000' };
  let publicEndpointRejected = false;
  let publicSigningEndpointRejected = false;
  try { loadStorageConfig({ ...fixture, MINIO_ENDPOINT: 'https://storage.example.invalid' }); }
  catch { publicEndpointRejected = true; }
  try { loadStorageConfig({ ...fixture, MINIO_SIGNING_ENDPOINT: 'https://storage.example.invalid' }); }
  catch { publicSigningEndpointRejected = true; }
  const driver = new S3Driver(loadStorageConfig(fixture));
  const signingEndpoint = 'http://127.0.0.1:9443';
  const split = new S3Driver(loadStorageConfig({ ...fixture, MINIO_SIGNING_ENDPOINT: signingEndpoint }));
  try {
    const id = '00000000-0000-4000-8000-000000000001';
    const transfer = await driver.getDownloadUrl(`${id}/${id}/${id}/1_fictional.pdf`);
    const separated = await split.getDownloadUrl(`${id}/${id}/${id}/1_fictional.pdf`);
    return { mode: 'OFFLINE_REAL_CODE', publicEndpointRejected, publicSigningEndpointRejected,
      independentLoopbackSigning: new URL(separated.url).origin === signingEndpoint,
      signedOriginIsLoopback: new URL(transfer.url).hostname === '127.0.0.1' };
  } finally { driver.close(); split.close(); }
}
