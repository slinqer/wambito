DELETE FROM "pairing_requests";--> statement-breakpoint
CREATE TABLE "record_purges" (
	"user_id" text PRIMARY KEY NOT NULL,
	"through_version" bigint NOT NULL
);
--> statement-breakpoint
ALTER TABLE "pairing_requests" ALTER COLUMN "public_key" DROP NOT NULL;--> statement-breakpoint
ALTER TABLE "key_wraps" ADD COLUMN "attestation" "bytea";--> statement-breakpoint
ALTER TABLE "pairing_requests" ADD COLUMN "commitment" "bytea" NOT NULL;--> statement-breakpoint
ALTER TABLE "pairing_requests" ADD COLUMN "approver_key" "bytea";--> statement-breakpoint
ALTER TABLE "pairing_requests" ADD COLUMN "key_v" smallint;--> statement-breakpoint
ALTER TABLE "record_purges" ADD CONSTRAINT "record_purges_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "key_wraps" ADD CONSTRAINT "key_wraps_device_attestation" CHECK ("key_wraps"."kind" <> 'device' or ("key_wraps"."attestation" is not null and octet_length("key_wraps"."attestation") = 32 and "key_wraps"."public_key" is not null and octet_length("key_wraps"."public_key") = 32));--> statement-breakpoint
ALTER TABLE "pairing_requests" ADD CONSTRAINT "pairing_requests_commitment_len" CHECK (octet_length("pairing_requests"."commitment") = 32);--> statement-breakpoint
ALTER TABLE "pairing_requests" ADD CONSTRAINT "pairing_requests_approver_key_len" CHECK ("pairing_requests"."approver_key" is null or octet_length("pairing_requests"."approver_key") = 32);--> statement-breakpoint
ALTER TABLE "pairing_requests" ADD CONSTRAINT "pairing_requests_public_key_len" CHECK ("pairing_requests"."public_key" is null or octet_length("pairing_requests"."public_key") = 32);--> statement-breakpoint
ALTER TABLE "record_purges" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "record_purges" FORCE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE POLICY tenant_isolation ON "record_purges" FOR ALL
  USING (user_id = current_setting('app.user_id', true))
  WITH CHECK (user_id = current_setting('app.user_id', true));
