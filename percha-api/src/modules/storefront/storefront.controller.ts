import { Body, Controller, Get, Header, HttpCode, Param, ParseUUIDPipe, Post, Put, Query, Res } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import type { Response } from 'express';
import { randomBytes } from 'node:crypto';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { Public, RequirePermissions } from '../../common/authz/decorators';
import { IdempotencyKey } from '../../common/idempotency';
import { ZodPipe } from '../../common/zod.pipe';
import { CatalogSettingsSchema, OrderStatusSchema, PublicOrderSchema, StorefrontService } from './storefront.service';
import { notFoundPage, storefrontPage } from './page';
import { DomainError } from '../../common/domain-error';

const Slug = z.string().regex(/^[a-z0-9-]{3,40}$/i);

@Controller()
export class StorefrontController {
  constructor(private readonly store: StorefrontService) {}

  // ---------------- público (sin sesión)

  /** Página del catálogo: https://…/c/<slug> */
  @Public()
  @Get('c/:slug')
  @Throttle({ default: { limit: 120, ttl: 60_000 } })
  async page(@Param('slug', new ZodPipe(Slug)) slug: string, @Res() res: Response) {
    let data: Awaited<ReturnType<StorefrontService['publicCatalog']>>;
    try {
      data = await this.store.publicCatalog(slug);
    } catch (e) {
      if (!(e instanceof DomainError) || e.kind !== 'not_found') throw e;
      res.status(404).setHeader('Content-Type', 'text/html; charset=utf-8').setHeader('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'").send(notFoundPage());
      return;
    }
    const nonce = randomBytes(16).toString('base64');
    const image = data.products.find((p) => p.imageUrl)?.imageUrl ?? null;
    res
      .status(200)
      .setHeader('Content-Type', 'text/html; charset=utf-8')
      .setHeader('Cache-Control', 'public, max-age=60')
      .setHeader(
        'Content-Security-Policy',
        `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'nonce-${nonce}' 'unsafe-inline'; img-src 'self' https: data:; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
      )
      .send(storefrontPage({ slug, nonce, data, title: data.store.name, description: data.store.description ?? `Catálogo de ${data.store.name}`, image, url: this.store.url(slug) }));
  }

  @Public()
  @Get('public/catalog/:slug')
  @Header('Cache-Control', 'public, max-age=60')
  @Throttle({ default: { limit: 120, ttl: 60_000 } })
  catalog(@Param('slug', new ZodPipe(Slug)) slug: string) {
    return this.store.publicCatalog(slug);
  }

  @Public()
  @Get('public/catalog/:slug/products/:id')
  @Header('Cache-Control', 'public, max-age=30')
  @Throttle({ default: { limit: 240, ttl: 60_000 } })
  product(@Param('slug', new ZodPipe(Slug)) slug: string, @Param('id', ParseUUIDPipe) id: string) {
    return this.store.publicProduct(slug, id);
  }

  /** Pedido del cliente: pocos por IP (evita spam). */
  @Public()
  @Post('public/catalog/:slug/orders')
  @Throttle({ default: { limit: 5, ttl: 600_000 } })
  order(@Param('slug', new ZodPipe(Slug)) slug: string, @Body(new ZodPipe(PublicOrderSchema)) b: z.infer<typeof PublicOrderSchema>, @IdempotencyKey() key?: string) {
    return this.store.createOrder(slug, b, key);
  }

  // ---------------- tienda

  @Get('catalog/settings')
  @RequirePermissions('settings.manage')
  settings(@CurrentUser() u: AuthUser) {
    return this.store.getSettings(u);
  }

  @Put('catalog/settings')
  @RequirePermissions('settings.manage')
  save(@CurrentUser() u: AuthUser, @Body(new ZodPipe(CatalogSettingsSchema)) b: z.infer<typeof CatalogSettingsSchema>) {
    return this.store.saveSettings(u, b);
  }

  @Put('catalog/products/:id/published')
  @RequirePermissions('catalog.write')
  publish(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(z.object({ published: z.boolean() }))) b: { published: boolean }) {
    return this.store.setPublished(u, id, b.published);
  }

  @Get('catalog/orders')
  @RequirePermissions('sales.read')
  orders(@CurrentUser() u: AuthUser, @Query(new ZodPipe(z.object({ status: z.enum(['new', 'contacted', 'completed', 'cancelled']).optional() }))) q: { status?: string }) {
    return this.store.listOrders(u, q.status);
  }

  @Get('catalog/orders/:id')
  @RequirePermissions('sales.read')
  orderDetail(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.store.getOrder(u, id);
  }

  @Post('catalog/orders/:id/status')
  @HttpCode(200)
  @RequirePermissions('sales.create')
  status(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(OrderStatusSchema)) b: z.infer<typeof OrderStatusSchema>) {
    return this.store.setStatus(u, id, b.status);
  }

  @Post('catalog/orders/:id/customer')
  @HttpCode(200)
  @RequirePermissions('customers.write')
  linkCustomer(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.store.linkCustomer(u, id);
  }
}
