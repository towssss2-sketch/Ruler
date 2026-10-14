import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { z } from 'zod';
import { PrismaRepository } from '../../prisma.repository';
import { AuthRedisService } from './auth-redis.service';
import { PasswordService } from './password.service';
import { registerInput } from './auth-input';
import { SessionService, TokenPair } from './session.service';
import { UserService } from '../user/user.service';
import { PublicUser, publicUser } from '../user/user-view';

@Injectable()
export class AuthService {
  constructor(private readonly repository: PrismaRepository, private readonly passwords: PasswordService,
    private readonly redis: AuthRedisService, private readonly sessions: SessionService, private readonly users: UserService) {}

  /** 验证一次性邮箱码后创建免费账号；用户与注册审计同一事务落库。 */
  async register(input: z.infer<typeof registerInput>): Promise<PublicUser> {
    if (!await this.redis.consumeCode(input.email, input.code)) throw new UnauthorizedException();
    const passwordHash = await this.passwords.hash(input.password);
    try {
      return await this.repository.db.$transaction(async (tx): Promise<PublicUser> => {
        const user = await tx.user.create({ data: { email: input.email, name: input.name, passwordHash,
          wallet: { create: {} } } });
        await tx.auditLog.create({ data: { userId: user.id, action: 'AUTH_REGISTER', resourceType: 'User', resourceId: user.id } });
        return publicUser(user);
      });
    } catch (error: unknown) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') throw new ConflictException();
      throw error;
    }
  }

  /** 错误密码、未注册、已删除账号统一 401，并执行同成本的密码处理。 */
  async login(email: string, password: string): Promise<TokenPair> {
    const user = await this.repository.db.user.findUnique({ where: { email } });
    const verified = await this.passwords.verify(password, user?.passwordHash ?? 'missing');
    if (!user || user.deletedAt || !verified) throw new UnauthorizedException();
    return this.sessions.start(user.id);
  }

  /** 当前账号读取只返回公开字段，软删除立即拒绝。 */
  async me(userId: string): Promise<PublicUser> {
    return this.users.me(userId);
  }
}
