import { Global, Module } from '@nestjs/common';
import { AttemptsService } from './attempts.service';

@Global()
@Module({ providers: [AttemptsService], exports: [AttemptsService] })
export class SecurityModule {}
