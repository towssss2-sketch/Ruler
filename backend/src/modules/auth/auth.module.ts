import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { PrismaModule } from '../../prisma.module';
import { AUTH_CONFIG, loadAuthConfig } from './auth-config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { PasswordService } from './password.service';
import { AuthRedisService } from './auth-redis.service';
import { DevelopmentMailbox } from './development-mailbox';
import { SessionService } from './session.service';
import { TokenCodecService } from './token-codec.service';
import { JwtAuthGuard } from './jwt-auth.guard';
import { AuthRateGuard } from './auth-rate.guard';
import { UserModule } from '../user/user.module';
import { RUNTIME_PROFILE, loadRuntimeProfile } from '../../runtime-profile';
import { DevelopmentEntryGuard } from './development-entry.guard';

@Module({ imports: [PrismaModule, UserModule], controllers: [AuthController], providers: [
  { provide: AUTH_CONFIG, useFactory: (): ReturnType<typeof loadAuthConfig> => loadAuthConfig(process.env) },
  { provide: RUNTIME_PROFILE, useFactory: (): ReturnType<typeof loadRuntimeProfile> => loadRuntimeProfile(process.env) },
  PasswordService, AuthRedisService, DevelopmentMailbox, SessionService, TokenCodecService, AuthService,
  { provide: APP_GUARD, useClass: DevelopmentEntryGuard },
  { provide: APP_GUARD, useClass: AuthRateGuard }, { provide: APP_GUARD, useClass: JwtAuthGuard },
], exports: [SessionService, DevelopmentMailbox] })
export class AuthModule {}
