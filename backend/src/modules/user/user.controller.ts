import { Controller, Get } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthPrincipal, CurrentUser } from '../auth/auth-decorators';
import { UserService } from './user.service';
import { PublicUser } from './user-view';

@Controller('users') @ApiTags('当前用户') @ApiBearerAuth()
export class UserController {
  constructor(private readonly users: UserService) {}

  /** 全局 JWT 守卫核验后才读取当前用户，没有任意用户 ID 查询接口。 */
  @Get('me')
  me(@CurrentUser() principal: AuthPrincipal): Promise<PublicUser> { return this.users.me(principal.userId); }
}
