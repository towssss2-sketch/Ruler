import { Body, Controller, Get, HttpCode, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiBody, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthService } from './auth.service';
import { PublicUser } from '../user/user-view';
import { AuthPrincipal, CurrentUser, PublicRoute } from './auth-decorators';
import { AuthRedisService } from './auth-redis.service';
import { RateLimit } from './auth-rate.guard';
import { loginInput, parseInput, refreshInput, registerInput, requestCodeInput } from './auth-input';
import { SessionService, TokenPair } from './session.service';
import { DevelopmentEntry } from './development-entry.guard';

const fields = { email: { type: 'string', format: 'email' }, password: { type: 'string', minLength: 12, maxLength: 128 } };

@ApiTags('开发鉴权')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService, private readonly redis: AuthRedisService, private readonly sessions: SessionService) {}

  /** 为虚构邮箱生成验证码；不通过接口响应或日志返回验证码。 */
  @Post('verification-code') @DevelopmentEntry() @PublicRoute() @RateLimit('code') @HttpCode(200)
  @ApiOperation({ summary: '投递虚构邮箱验证码（真实邮件未接入）' })
  @ApiBody({ schema: { type: 'object', required: ['email'], properties: { email: fields.email } } })
  async requestCode(@Body() body: unknown): Promise<{ accepted: true }> {
    const input = parseInput(requestCodeInput, body);
    await this.redis.requestCode(input.email);
    return { accepted: true };
  }

  /** 邮箱验证码注册，拒绝额外字段和客户端提供的会员/用户标识。 */
  @Post('register') @DevelopmentEntry() @PublicRoute() @RateLimit('register')
  @ApiOperation({ summary: '邮箱验证码注册' })
  @ApiBody({ schema: { type: 'object', required: ['email', 'password', 'name', 'code'],
    properties: { ...fields, name: { type: 'string' }, code: { type: 'string', pattern: '^\\d{6}$' } } } })
  register(@Body() body: unknown): Promise<PublicUser> { return this.auth.register(parseInput(registerInput, body)); }

  /** 邮箱密码登录；短期 JWT 与随机刷新令牌类型分离。 */
  @Post('login') @PublicRoute() @RateLimit('login') @HttpCode(200)
  @ApiOperation({ summary: '登录（Access 2h / 会话 30d）' })
  @ApiBody({ schema: { type: 'object', required: ['email', 'password'], properties: fields } })
  login(@Body() body: unknown): Promise<TokenPair> {
    const input = parseInput(loginInput, body);
    return this.auth.login(input.email, input.password);
  }

  /** 单次刷新；旧凭据重放吊销会话，真实数据库即时生效。 */
  @Post('refresh') @PublicRoute() @RateLimit('refresh') @HttpCode(200)
  @ApiOperation({ summary: '轮换刷新令牌，重复使用会吊销会话' })
  @ApiBody({ schema: { type: 'object', required: ['refreshToken'], properties: { refreshToken: { type: 'string' } } } })
  refresh(@Body() body: unknown): Promise<TokenPair> { return this.sessions.refresh(parseInput(refreshInput, body).refreshToken); }

  /** 登出当前会话，Access 与 Refresh 同时失效。 */
  @Post('logout') @HttpCode(200) @ApiBearerAuth()
  async logout(@CurrentUser() principal: AuthPrincipal): Promise<{ loggedOut: true }> {
    await this.sessions.logout(principal);
    return { loggedOut: true };
  }

  /** 只返回最小当前用户字段，不泄露哈希、密文或会话凭据。 */
  @Get('me') @ApiBearerAuth()
  me(@CurrentUser() principal: AuthPrincipal): Promise<PublicUser> { return this.auth.me(principal.userId); }
}
