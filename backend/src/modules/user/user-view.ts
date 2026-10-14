import { User } from '@prisma/client';

export interface PublicUser { id: string; email: string | null; name: string; tier: string }

/** 最小用户视图；不把 ORM 哈希、密文或会话对象直接发送到客户端。 */
export function publicUser(user: User): PublicUser {
  return { id: user.id, email: user.email, name: user.name, tier: user.tier };
}
