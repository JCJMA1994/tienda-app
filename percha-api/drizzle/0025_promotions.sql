CREATE TYPE "public"."promotion_kind" AS ENUM('percent', 'buy_x_pay_y');--> statement-breakpoint
CREATE TYPE "public"."promotion_scope" AS ENUM('all', 'categories', 'products');--> statement-breakpoint
CREATE TABLE "promotions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"tenant_id" uuid NOT NULL,
	"name" text NOT NULL,
	"kind" "promotion_kind" NOT NULL,
	"percent_bp" integer,
	"buy_qty" integer,
	"pay_qty" integer,
	"scope" "promotion_scope" DEFAULT 'all' NOT NULL,
	"category_ids" uuid[] DEFAULT '{}' NOT NULL,
	"product_ids" uuid[] DEFAULT '{}' NOT NULL,
	"starts_at" timestamp with time zone NOT NULL,
	"ends_at" timestamp with time zone,
	"active" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "promotions_tenant_id_uq" UNIQUE("tenant_id","id")
);
--> statement-breakpoint
ALTER TABLE "sale_items" ADD COLUMN "promo_discount_cents" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "sale_items" ADD COLUMN "promotion_id" uuid;--> statement-breakpoint
ALTER TABLE "sales" ADD COLUMN "promo_discount_cents" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "promotions" ADD CONSTRAINT "promotions_tenant_id_tenants_id_fk" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE no action ON UPDATE no action;