CREATE TABLE "sunat_padron" (
	"ruc" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"status" text,
	"condition" text,
	"ubigeo" text,
	"address" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
