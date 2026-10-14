import {
  createCipheriv, createDecipheriv, createHmac, hkdfSync, randomBytes,
} from 'node:crypto';

const HEADER = Buffer.from('GCM1');
const NONCE_LENGTH = 12;
const TAG_LENGTH = 16;
const PAYLOAD_OFFSET = HEADER.length + NONCE_LENGTH + TAG_LENGTH;

/** 业务只依赖此接口；后续可通过独立实现替换加密算法。 */
export interface SensitiveFieldCipher {
  encrypt(value: string, context: string): Uint8Array<ArrayBuffer>;
  decrypt(value: Uint8Array, context: string): string;
  blindIndex(value: string, purpose: string): Uint8Array<ArrayBuffer>;
}

/** AES-256-GCM 字段加密。密钥由调用层注入，不生成或保存生产密钥。 */
export class EncryptionService implements SensitiveFieldCipher {
  private readonly key: Buffer;
  private readonly indexKey: Buffer;

  /** 接收 32 字节主密钥并复制；长度不符抛出固定错误，不输出密钥。 */
  constructor(key: Uint8Array) {
    if (key.byteLength !== 32) throw new Error('加密密钥必须为 32 字节');
    this.key = Buffer.from(key);
    this.indexKey = Buffer.from(hkdfSync('sha256', this.key, Buffer.alloc(0), 'ruler:blind-index:v1', 32));
  }

  /** 加密 UTF-8 字符串；context 应为模型/记录 UUID/字段，用 AAD 阻止密文错绑。 */
  encrypt(value: string, context: string): Uint8Array<ArrayBuffer> {
    this.validatePurpose(context);
    if (value.length === 0) throw new Error('敏感字段不能为空');
    const nonce = randomBytes(NONCE_LENGTH);
    const cipher = createCipheriv('aes-256-gcm', this.key, nonce);
    cipher.setAAD(Buffer.from(context, 'utf8'));
    const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
    return new Uint8Array(Buffer.concat([HEADER, nonce, cipher.getAuthTag(), ciphertext]));
  }

  /** 还原字段；错误密钥、上下文、格式或篡改统一抛固定错误，绝不返回部分明文。 */
  decrypt(value: Uint8Array, context: string): string {
    try {
      this.validatePurpose(context);
      const payload = Buffer.from(value);
      if (payload.length <= PAYLOAD_OFFSET || !payload.subarray(0, HEADER.length).equals(HEADER)) {
        throw new Error('密文格式无效');
      }
      const nonceEnd = HEADER.length + NONCE_LENGTH;
      const decipher = createDecipheriv('aes-256-gcm', this.key, payload.subarray(HEADER.length, nonceEnd));
      decipher.setAAD(Buffer.from(context, 'utf8'));
      decipher.setAuthTag(payload.subarray(nonceEnd, PAYLOAD_OFFSET));
      return Buffer.concat([decipher.update(payload.subarray(PAYLOAD_OFFSET)), decipher.final()]).toString('utf8');
    } catch {
      throw new Error('敏感字段解密失败');
    }
  }

  /** 返回带域隔离的 HMAC-SHA-256 盲索引；调用者先规范化值，不能使用无密钥手机号摘要。 */
  blindIndex(value: string, purpose: string): Uint8Array<ArrayBuffer> {
    this.validatePurpose(purpose);
    if (value.length === 0) throw new Error('敏感字段不能为空');
    return new Uint8Array(createHmac('sha256', this.indexKey).update(JSON.stringify([purpose, value])).digest());
  }

  private validatePurpose(purpose: string): void {
    if (purpose.trim().length === 0 || purpose.length > 512 || purpose.includes('\0')) {
      throw new Error('必须指定有效的敏感字段上下文');
    }
  }
}
