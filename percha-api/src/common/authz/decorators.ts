import { SetMetadata } from '@nestjs/common';
import type { Permission } from './permissions';

export const IS_PUBLIC = 'isPublic';
export const REQUIRED_PERMISSIONS = 'requiredPermissions';

/** Endpoint sin autenticación (login, registro...). */
export const Public = () => SetMetadata(IS_PUBLIC, true);

/** Exige TODOS los permisos indicados. */
export const RequirePermissions = (...permissions: Permission[]) =>
  SetMetadata(REQUIRED_PERMISSIONS, permissions);
