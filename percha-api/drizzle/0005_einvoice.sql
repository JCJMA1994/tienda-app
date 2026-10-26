CREATE TYPE "public"."einvoice_kind" AS ENUM('boleta', 'factura', 'nota_credito');--> statement-breakpoint
CREATE TYPE "public"."einvoice_series_kind" AS ENUM('boleta', 'factura', 'nc_boleta', 'nc_factura');--> statement-breakpoint
CREATE TYPE "public"."einvoice_status" AS ENUM('pending', 'accepted', 'rejected', 'error');--> statement-breakpoint
CREATE TABLE "einvoice_documents" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"tenant_id" uuid NOT NULL,
	"branch_id" uuid NOT NULL,
	"sale_id" uuid,
	"return_id" uuid,
	"reference_id" uuid,
	"kind" "einvoice_kind" NOT NULL,
	"serie" text NOT NULL,
	"numero" integer NOT NULL,
	"customer_doc_type" text NOT NULL,
	"customer_doc_number" text,
	"customer_name" text,
	"total_cents" integer NOT NULL,
	"status" "einvoice_status" DEFAULT 'pending' NOT NULL,
	"provider" text NOT NULL,
	"payload" jsonb NOT NULL,
	"attempts" integer DEFAULT 0 NOT NULL,
	"last_error" text,
	"sunat_description" text,
	"pdf_url" text,
	"hash" text,
	"qr" text,
	"sent_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "einvoice_documents_serie_numero_uq" UNIQUE("tenant_id","serie","numero"),
	CONSTRAINT "einvoice_documents_tenant_id_uq" UNIQUE("tenant_id","id")
);
--> statement-breakpoint
CREATE TABLE "einvoice_series" (
	"tenant_id" uuid NOT NULL,
	"branch_id" uuid NOT NULL,
	"kind" "einvoice_series_kind" NOT NULL,
	"serie" text NOT NULL,
	CONSTRAINT "einvoice_series_tenant_id_branch_id_kind_pk" PRIMARY KEY("tenant_id","branch_id","kind"),
	CONSTRAINT "einvoice_series_tenant_serie_uq" UNIQUE("tenant_id","serie")
);
--> statement-breakpoint
CREATE TABLE "einvoice_settings" (
	"tenant_id" uuid PRIMARY KEY NOT NULL,
	"enabled" boolean DEFAULT false NOT NULL,
	"provider" text DEFAULT 'nubefact' NOT NULL,
	"legal_name" text,
	"fiscal_address" text,
	"api_url" text,
	"token_enc" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "einvoice_documents" ADD CONSTRAINT "einvoice_documents_tenant_id_tenants_id_fk" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "einvoice_documents" ADD CONSTRAINT "einvoice_documents_branch_fk" FOREIGN KEY ("tenant_id","branch_id") REFERENCES "public"."branches"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "einvoice_documents" ADD CONSTRAINT "einvoice_documents_sale_fk" FOREIGN KEY ("tenant_id","sale_id") REFERENCES "public"."sales"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "einvoice_documents" ADD CONSTRAINT "einvoice_documents_return_fk" FOREIGN KEY ("tenant_id","return_id") REFERENCES "public"."returns"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "einvoice_series" ADD CONSTRAINT "einvoice_series_tenant_id_tenants_id_fk" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "einvoice_series" ADD CONSTRAINT "einvoice_series_branch_fk" FOREIGN KEY ("tenant_id","branch_id") REFERENCES "public"."branches"("tenant_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "einvoice_settings" ADD CONSTRAINT "einvoice_settings_tenant_id_tenants_id_fk" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "einvoice_documents_status_idx" ON "einvoice_documents" USING btree ("status","created_at");--> statement-breakpoint
CREATE INDEX "einvoice_documents_sale_idx" ON "einvoice_documents" USING btree ("sale_id");