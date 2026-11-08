CREATE SEQUENCE "records_version_seq";--> statement-breakpoint
CREATE TABLE "key_wraps" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"kind" text NOT NULL,
	"ref" text,
	"key_v" smallint NOT NULL,
	"wrapped" bytea NOT NULL,
	"public_key" bytea,
	"label" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_used_at" timestamp with time zone,
	CONSTRAINT "key_wraps_kind" CHECK ("key_wraps"."kind" in ('passkey', 'recovery', 'device', 'assistant'))
);
--> statement-breakpoint
CREATE TABLE "pairing_requests" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"code" text NOT NULL,
	"public_key" bytea NOT NULL,
	"sealed" bytea,
	"expires_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "records" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"type" text NOT NULL,
	"version" bigint DEFAULT nextval('records_version_seq') NOT NULL,
	"deleted" boolean DEFAULT false NOT NULL,
	"key_v" smallint NOT NULL,
	"enc_v" smallint NOT NULL,
	"body" bytea,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "records_deleted_body" CHECK ("records"."deleted" = ("records"."body" is null))
);
--> statement-breakpoint
ALTER TABLE "key_wraps" ADD CONSTRAINT "key_wraps_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pairing_requests" ADD CONSTRAINT "pairing_requests_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "records" ADD CONSTRAINT "records_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "key_wraps_one_recovery" ON "key_wraps" USING btree ("user_id") WHERE "key_wraps"."kind" = 'recovery';--> statement-breakpoint
CREATE UNIQUE INDEX "key_wraps_ref" ON "key_wraps" USING btree ("user_id","kind","ref") WHERE "key_wraps"."ref" is not null;--> statement-breakpoint
CREATE UNIQUE INDEX "pairing_requests_code" ON "pairing_requests" USING btree ("user_id","code");--> statement-breakpoint
CREATE INDEX "records_user_version" ON "records" USING btree ("user_id","version");--> statement-breakpoint
ALTER TABLE "records" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "records" FORCE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE POLICY tenant_isolation ON "records" FOR ALL
  USING (user_id = current_setting('app.user_id', true))
  WITH CHECK (user_id = current_setting('app.user_id', true));
--> statement-breakpoint
ALTER TABLE "key_wraps" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "key_wraps" FORCE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE POLICY tenant_isolation ON "key_wraps" FOR ALL
  USING (user_id = current_setting('app.user_id', true))
  WITH CHECK (user_id = current_setting('app.user_id', true));
--> statement-breakpoint
ALTER TABLE "pairing_requests" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "pairing_requests" FORCE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE POLICY tenant_isolation ON "pairing_requests" FOR ALL
  USING (user_id = current_setting('app.user_id', true))
  WITH CHECK (user_id = current_setting('app.user_id', true));
