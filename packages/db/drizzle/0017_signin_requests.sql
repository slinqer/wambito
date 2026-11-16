CREATE TABLE "signin_requests" (
	"id" uuid PRIMARY KEY NOT NULL,
	"code" text NOT NULL,
	"commitment" "bytea" NOT NULL,
	"poll_hash" "bytea" NOT NULL,
	"label" text NOT NULL,
	"remember" boolean NOT NULL,
	"user_id" text,
	"approver_key" "bytea",
	"public_key" "bytea",
	"key_v" smallint,
	"sealed" "bytea",
	"expires_at" timestamp with time zone NOT NULL,
	CONSTRAINT "signin_requests_code_unique" UNIQUE("code"),
	CONSTRAINT "signin_requests_commitment_len" CHECK (octet_length("signin_requests"."commitment") = 32),
	CONSTRAINT "signin_requests_poll_hash_len" CHECK (octet_length("signin_requests"."poll_hash") = 32),
	CONSTRAINT "signin_requests_label_len" CHECK (char_length("signin_requests"."label") between 1 and 64),
	CONSTRAINT "signin_requests_approver_key_len" CHECK ("signin_requests"."approver_key" is null or octet_length("signin_requests"."approver_key") = 32),
	CONSTRAINT "signin_requests_public_key_len" CHECK ("signin_requests"."public_key" is null or octet_length("signin_requests"."public_key") = 32)
);
--> statement-breakpoint
ALTER TABLE "signin_requests" ADD CONSTRAINT "signin_requests_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;