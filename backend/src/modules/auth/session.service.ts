import { Injectable, UnauthorizedException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { PrismaRepository } from '../../prisma.repository';
import { AuthPrincipal } from './auth-decorators';
import { TokenCodecService } from './token-codec.service';

export interface TokenPair {
  accessToken: string; refreshToken: string; tokenType: 'Bearer'; expiresIn: number; refreshExpiresAt: string;
}
interface SessionResult { userId: string; sessionId: string; expiresAt: Date; refreshToken: string }
const digest = (token: string): string => createHash('sha256').update(token).digest('hex');

/** 数据库会话是唯一有效性依据；轮换、重放吊销与登出在事务内执行。 */
@Injectable()
export class SessionService {
  constructor(private readonly repository: PrismaRepository, private readonly codec: TokenCodecService) {}

  /** 登录建立三十天绝对有效期的会话，只保存随机刷新凭据的摘要。 */
  async start(userId: string): Promise<TokenPair> {
    const refreshToken = randomBytes(32).toString('base64url');
    const sessionId = randomUUID();
    const expiresAt = new Date(Date.now() + 30 * 86_400_000);
    await this.repository.db.$transaction(async (tx): Promise<void> => {
      await tx.authSession.create({ data: { id: sessionId, userId, expiresAt,
        refreshTokens: { create: { tokenHash: digest(refreshToken) } } } });
      await this.audit(tx, userId, sessionId, 'AUTH_LOGIN');
    });
    return this.pair({ userId, sessionId, expiresAt, refreshToken });
  }

  /** 行锁串行化同一会话轮换；已消费凭据再次使用会吊销整条会话。 */
  async refresh(refreshToken: string): Promise<TokenPair> {
    const tokenHash = digest(refreshToken);
    const existing = await this.repository.db.refreshCredential.findUnique({ where: { tokenHash } });
    if (!existing) throw new UnauthorizedException();
    const result = await this.repository.db.$transaction(async (tx): Promise<SessionResult | null> => {
      await tx.$queryRaw`SELECT id FROM "AuthSession" WHERE id=${existing.sessionId}::uuid FOR UPDATE`;
      const token = await tx.refreshCredential.findUnique({ where: { tokenHash }, include: { session: { include: { user: true } } } });
      const session = token?.session;
      const now = new Date();
      if (!token || !session || token.deletedAt || session.revokedAt || session.deletedAt ||
        session.expiresAt <= now || session.user.deletedAt) return null;
      if (token.consumedAt) {
        await tx.authSession.update({ where: { id: session.id }, data: { revokedAt: now } });
        await this.audit(tx, session.userId, session.id, 'AUTH_REFRESH_REPLAY');
        return null;
      }
      await tx.refreshCredential.update({ where: { id: token.id }, data: { consumedAt: now } });
      const next = randomBytes(32).toString('base64url');
      await tx.refreshCredential.create({ data: { sessionId: session.id, tokenHash: digest(next) } });
      await this.audit(tx, session.userId, session.id, 'AUTH_REFRESH');
      return { userId: session.userId, sessionId: session.id, expiresAt: session.expiresAt, refreshToken: next };
    });
    // 重放吊销先提交，再抛错；不能把吊销写入与异常一起回滚。
    if (!result) throw new UnauthorizedException();
    return this.pair(result);
  }

  /** 每次受保护请求实时核验会话和用户；登出、删号、过期立即生效。 */
  async authenticate(accessToken: string): Promise<AuthPrincipal> {
    const principal = await this.codec.verify(accessToken);
    const session = await this.repository.db.authSession.findFirst({ where: {
      id: principal.sessionId, userId: principal.userId, revokedAt: null, deletedAt: null,
      expiresAt: { gt: new Date() }, user: { deletedAt: null },
    }, select: { id: true } });
    if (!session) throw new UnauthorizedException();
    return principal;
  }

  /** 吊销当前会话；不影响另一个设备的独立会话，不记录令牌内容。 */
  async logout(principal: AuthPrincipal): Promise<void> {
    await this.repository.db.$transaction(async (tx): Promise<void> => {
      const result = await tx.authSession.updateMany({ where: { id: principal.sessionId,
        userId: principal.userId, revokedAt: null }, data: { revokedAt: new Date() } });
      if (result.count) await this.audit(tx, principal.userId, principal.sessionId, 'AUTH_LOGOUT');
    });
  }

  private async pair(result: SessionResult): Promise<TokenPair> {
    return { accessToken: await this.codec.sign(result.userId, result.sessionId),
      refreshToken: result.refreshToken, tokenType: 'Bearer', expiresIn: 7200,
      refreshExpiresAt: result.expiresAt.toISOString() };
  }

  private async audit(tx: Prisma.TransactionClient, userId: string, sessionId: string, action: string): Promise<void> {
    await tx.auditLog.create({ data: { userId, action, resourceType: 'AuthSession', resourceId: sessionId } });
  }
}
