import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PrismaRepository } from '../../prisma.repository';
import { PublicUser, publicUser } from './user-view';

@Injectable()
export class UserService {
  constructor(private readonly repository: PrismaRepository) {}

  /** 获取已核验身份的当前用户，软删除账号立即拒绝。 */
  async me(userId: string): Promise<PublicUser> {
    const user = await this.repository.db.user.findFirst({ where: { id: userId, deletedAt: null } });
    if (!user) throw new UnauthorizedException();
    return publicUser(user);
  }
}
