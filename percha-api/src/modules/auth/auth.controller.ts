import { Body, Controller, Get, HttpCode, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { ZodPipe } from '../../common/zod.pipe';
import { Public } from '../../common/authz/decorators';
import {
  AcceptInvitationSchema,
  AuthService,
  ChangePasswordSchema,
  ForgotPasswordSchema,
  LoginSchema,
  PinSchema,
  RegisterSchema,
  ResetPasswordSchema,
  TwoFactorDisableSchema,
  TwoFactorVerifySchema,
} from './auth.service';
import { TokenService } from './token.service';

const RefreshSchema = z.object({ refreshToken: z.string().min(20) });

// El límite por IP lo aplica el ThrottlerGuard global; aquí solo se ajusta por ruta con @Throttle.
@Controller('auth')
export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly tokens: TokenService,
  ) {}

  @Public()
  @Post('register')
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  register(@Body(new ZodPipe(RegisterSchema)) body: z.infer<typeof RegisterSchema>) {
    return this.auth.register(body);
  }

  @Public()
  @Post('login')
  @HttpCode(200)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  login(@Body(new ZodPipe(LoginSchema)) body: z.infer<typeof LoginSchema>) {
    return this.auth.login(body);
  }

  @Public()
  @Post('refresh')
  @HttpCode(200)
  refresh(@Body(new ZodPipe(RefreshSchema)) body: z.infer<typeof RefreshSchema>) {
    return this.tokens.rotate(body.refreshToken);
  }

  @Public()
  @Post('logout')
  @HttpCode(204)
  async logout(@Body(new ZodPipe(RefreshSchema)) body: z.infer<typeof RefreshSchema>) {
    await this.tokens.revoke(body.refreshToken);
  }

  @Public()
  @Post('invitations/accept')
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  accept(@Body(new ZodPipe(AcceptInvitationSchema)) body: z.infer<typeof AcceptInvitationSchema>) {
    return this.auth.acceptInvitation(body);
  }

  /** Cambio de vendedor por PIN en el POS. Límite estricto: un PIN de 4 dígitos es adivinable. */
  @Post('pin')
  @HttpCode(200)
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  pin(@CurrentUser() user: AuthUser, @Body(new ZodPipe(PinSchema)) body: z.infer<typeof PinSchema>) {
    return this.auth.switchByPin(user, body);
  }

  @Post('password')
  @HttpCode(200)
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  changePassword(@CurrentUser() user: AuthUser, @Body(new ZodPipe(ChangePasswordSchema)) body: z.infer<typeof ChangePasswordSchema>) {
    return this.auth.changePassword(user, body);
  }

  // ---- Verificación en dos pasos
  @Public()
  @Post('2fa/verify')
  @HttpCode(200)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  verify2fa(@Body(new ZodPipe(TwoFactorVerifySchema)) body: z.infer<typeof TwoFactorVerifySchema>) {
    return this.auth.verifyTwoFactor(body);
  }

  @Post('2fa/setup')
  @HttpCode(200)
  setup2fa(@CurrentUser() user: AuthUser) {
    return this.auth.setupTwoFactor(user);
  }

  @Post('2fa/enable')
  @HttpCode(200)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  enable2fa(@CurrentUser() user: AuthUser, @Body(new ZodPipe(z.object({ code: z.string().regex(/^\d{6}$/) }))) body: { code: string }) {
    return this.auth.enableTwoFactor(user, body.code);
  }

  @Post('2fa/disable')
  @HttpCode(200)
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  disable2fa(@CurrentUser() user: AuthUser, @Body(new ZodPipe(TwoFactorDisableSchema)) body: z.infer<typeof TwoFactorDisableSchema>) {
    return this.auth.disableTwoFactor(user, body);
  }

  // ---- Recuperar contraseña
  @Public()
  @Post('password/forgot')
  @HttpCode(202)
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  forgot(@Body(new ZodPipe(ForgotPasswordSchema)) body: z.infer<typeof ForgotPasswordSchema>) {
    return this.auth.forgotPassword(body.email);
  }

  @Public()
  @Post('password/reset')
  @HttpCode(200)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  reset(@Body(new ZodPipe(ResetPasswordSchema)) body: z.infer<typeof ResetPasswordSchema>) {
    return this.auth.resetPassword(body);
  }

  @Post('logout-all')
  @HttpCode(204)
  async logoutAll(@CurrentUser() user: AuthUser) {
    await this.auth.logoutEverywhere(user);
  }

  @Get('me')
  me(@CurrentUser() user: AuthUser) {
    return this.auth.me(user);
  }
}
