CREATE TYPE "public"."layaway_status" AS ENUM('open', 'completed', 'cancelled');--> statement-breakpoint
CREATE TYPE "public"."store_credit_kind" AS ENUM('refund', 'gift', 'courtesy');--> statement-breakpoint
ALTER TYPE "public"."movement_type" ADD VALUE 'layaway_reserve';--> statement-breakpoint
ALTER TYPE "public"."movement_type" ADD VALUE 'layaway_release';--> statement-breakpoint
ALTER TYPE "public"."payment_method" ADD VALUE 'store_credit';--> statement-breakpoint
ALTER TYPE "public"."payment_method" ADD VALUE 'layaway';--> statement-breakpoint
CREATE TABLE "layaway_items" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"tenant_id" uuid NOT NULL,
	"layaway_id" uuid NOT NULL,
	"variant_id" uuid NOT NULL,
	"quantity" integer NOT NULL,
	"unit_price_cents" integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE "layaways" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"tenant_id" uuid NOT NULL,
	"number" integer NOT NULL,
	"branch_id" uuid NOT NULL,
	"customer_id" uuid NOT NULL,
	"status" "layaway_status" DEFAULT 'open' NOT NULL,
	"total_cents" integer NOT NULL,
	"paid_cents" integer DEFAULT 0 NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"notes" text,
	"created_by" uuid NOT NULL,
	"sale_id" uuid,
	"closed_at" timestamp with time zone,
	"close_reason" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "layaways_tenant_id_uq" UNIQUE("tenant_id","id"),
	CONSTRAINT "layaways_tenant_number_uq" UNIQUE("tenant_id","number"),
	CONSTRAINT "layaways_paid_ck" CHECK ("layaways"."paid_cents" >= 0 and "layaways"."paid_cents" <= "layaways"."total_cents")
);
--> statement-breakpoint
CREATE TABLE "store_credit_movements" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"tenant_id" uuid NOT NULL,
	"credit_id" uuid NOT NULL,
	"type" text NOT NULL,
	"delta_cents" integer NOT NULL,
	"balance_after" integer NOT NULL,
	"sale_id" uuid,
	"created_by" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "store_credits" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"tenant_id" uuid NOT NULL,
	"code_hash" text NOT NULL,
	"code_last4" text NOT NULL,
	"kind" "store_credit_kind" NOT NULL,
	"customer_id" uuid,
	"initial_cents" integer NOT NULL,
	"balance_cents" integer NOT NULL,
	"expires_at" timestamp with time zone,
	"note" text,
	"issued_by" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "store_credits_tenant_id_uq" UNIQUE("tenant_id","id"),
	CONSTRAINT "store_credits_code_uq" UNIQUE("code_hash"),
	CONSTRAINT "store_credits_balance_ck" CHECK ("store_credits"."balance_cents" >= 0 and "store_credits"."balance_cents" <= "store_credits"."initial_cents")
);
--> statement-breakpoint
ALTER TABLE "payments" ADD COLUMN "layaway_id" uuid;--> statement-breakpoint
ALTER TABLE "payments" ADD COLUMN "store_credit_id" uuid;--> statement-breakpoint
ALTER TABLE "layaway_items" ADD CONSTRAINT "layaway_items_tenant_id_tenants_id_fk" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "layaway_items" ADD CONSTRAINT "layaway_items_layaway_fk" FOREIGN KEY ("tenant_id","layaway_id") REFERENCES "public"."layaways"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "layaway_items" ADD CONSTRAINT "layaway_items_variant_fk" FOREIGN KEY ("tenant_id","variant_id") REFERENCES "public"."variants"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "layaways" ADD CONSTRAINT "layaways_tenant_id_tenants_id_fk" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "layaways" ADD CONSTRAINT "layaways_branch_fk" FOREIGN KEY ("tenant_id","branch_id") REFERENCES "public"."branches"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "layaways" ADD CONSTRAINT "layaways_customer_fk" FOREIGN KEY ("tenant_id","customer_id") REFERENCES "public"."customers"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "layaways" ADD CONSTRAINT "layaways_sale_fk" FOREIGN KEY ("tenant_id","sale_id") REFERENCES "public"."sales"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "store_credit_movements" ADD CONSTRAINT "store_credit_movements_tenant_id_tenants_id_fk" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "store_credit_movements" ADD CONSTRAINT "store_credit_movements_credit_fk" FOREIGN KEY ("tenant_id","credit_id") REFERENCES "public"."store_credits"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "store_credits" ADD CONSTRAINT "store_credits_tenant_id_tenants_id_fk" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "store_credits" ADD CONSTRAINT "store_credits_customer_fk" FOREIGN KEY ("tenant_id","customer_id") REFERENCES "public"."customers"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "store_credits" ADD CONSTRAINT "store_credits_issuer_fk" FOREIGN KEY ("tenant_id","issued_by") REFERENCES "public"."memberships"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "layaways_status_idx" ON "layaways" USING btree ("tenant_id","status","expires_at");--> statement-breakpoint
CREATE INDEX "store_credit_movements_credit_idx" ON "store_credit_movements" USING btree ("credit_id","created_at");--> statement-breakpoint
CREATE INDEX "store_credits_customer_idx" ON "store_credits" USING btree ("tenant_id","customer_id");