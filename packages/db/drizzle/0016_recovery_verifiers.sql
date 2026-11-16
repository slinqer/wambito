CREATE TABLE "recovery_verifiers" (
	"user_id" text PRIMARY KEY NOT NULL,
	"lookup_hash" "bytea" NOT NULL,
	"auth_hash" "bytea" NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "recovery_verifiers_lookup_hash_unique" UNIQUE("lookup_hash"),
	CONSTRAINT "recovery_verifiers_lookup_hash_len" CHECK (octet_length("recovery_verifiers"."lookup_hash") = 32),
	CONSTRAINT "recovery_verifiers_auth_hash_len" CHECK (octet_length("recovery_verifiers"."auth_hash") = 32)
);
--> statement-breakpoint
ALTER TABLE "recovery_verifiers" ADD CONSTRAINT "recovery_verifiers_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;