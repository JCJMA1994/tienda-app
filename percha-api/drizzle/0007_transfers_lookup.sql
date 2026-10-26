CREATE TYPE "public"."transfer_status" AS ENUM('in_transit', 'received', 'cancelled');--> statement-breakpoint
ALTER TYPE "public"."movement_type" ADD VALUE 'transfer_out';--> statement-breakpoint
ALTER TYPE "public"."movement_type" ADD VALUE 'transfer_in';--> statement-breakpoint
CREATE TABLE "identity_cache" (
	"doc_type" text NOT NULL,
	"doc_number" text NOT NULL,
	"data" jsonb NOT NULL,
	"fetched_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "identity_cache_doc_type_doc_number_pk" PRIMARY KEY("doc_type","doc_number")
);
--> statement-breakpoint
CREATE TABLE "transfer_items" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"tenant_id" uuid NOT NULL,
	"transfer_id" uuid NOT NULL,
	"variant_id" uuid NOT NULL,
	"quantity_sent" integer NOT NULL,
	"quantity_received" integer,
	"unit_cost_cents" integer NOT NULL,
	CONSTRAINT "transfer_items_transfer_variant_uq" UNIQUE("transfer_id","variant_id")
);
--> statement-breakpoint
CREATE TABLE "transfers" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"tenant_id" uuid NOT NULL,
	"number" integer NOT NULL,
	"from_branch_id" uuid NOT NULL,
	"to_branch_id" uuid NOT NULL,
	"status" "transfer_status" DEFAULT 'in_transit' NOT NULL,
	"notes" text,
	"sent_by" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"received_by" uuid,
	"received_at" timestamp with time zone,
	"receive_notes" text,
	CONSTRAINT "transfers_tenant_id_uq" UNIQUE("tenant_id","id"),
	CONSTRAINT "transfers_tenant_number_uq" UNIQUE("tenant_id","number")
);
--> statement-breakpoint
ALTER TABLE "transfer_items" ADD CONSTRAINT "transfer_items_tenant_id_tenants_id_fk" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transfer_items" ADD CONSTRAINT "transfer_items_transfer_fk" FOREIGN KEY ("tenant_id","transfer_id") REFERENCES "public"."transfers"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transfer_items" ADD CONSTRAINT "transfer_items_variant_fk" FOREIGN KEY ("tenant_id","variant_id") REFERENCES "public"."variants"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transfers" ADD CONSTRAINT "transfers_tenant_id_tenants_id_fk" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transfers" ADD CONSTRAINT "transfers_from_fk" FOREIGN KEY ("tenant_id","from_branch_id") REFERENCES "public"."branches"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transfers" ADD CONSTRAINT "transfers_to_fk" FOREIGN KEY ("tenant_id","to_branch_id") REFERENCES "public"."branches"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transfers" ADD CONSTRAINT "transfers_sender_fk" FOREIGN KEY ("tenant_id","sent_by") REFERENCES "public"."memberships"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "transfers_status_idx" ON "transfers" USING btree ("tenant_id","status");