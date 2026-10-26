ALTER TYPE "public"."einvoice_kind" ADD VALUE 'guia_remitente';--> statement-breakpoint
ALTER TYPE "public"."einvoice_series_kind" ADD VALUE 'guia';--> statement-breakpoint
ALTER TABLE "branches" ADD COLUMN "ubigeo" text;--> statement-breakpoint
ALTER TABLE "einvoice_documents" ADD COLUMN "transfer_id" uuid;--> statement-breakpoint
CREATE INDEX "einvoice_documents_transfer_idx" ON "einvoice_documents" USING btree ("transfer_id");