CREATE TABLE "key_links" (
	"user_id" text NOT NULL,
	"key_v" smallint NOT NULL,
	"link" "bytea" NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "key_links_user_id_key_v_pk" PRIMARY KEY("user_id","key_v"),
	CONSTRAINT "key_links_link_len" CHECK (octet_length("key_links"."link") = 60),
	CONSTRAINT "key_links_key_v" CHECK ("key_links"."key_v" >= 2)
);
--> statement-breakpoint
ALTER TABLE "key_wraps" ADD COLUMN "session_id" text;--> statement-breakpoint
ALTER TABLE "key_links" ADD CONSTRAINT "key_links_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "key_wraps" ADD CONSTRAINT "key_wraps_session_id_session_id_fk" FOREIGN KEY ("session_id") REFERENCES "public"."session"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "key_wraps" ADD CONSTRAINT "key_wraps_session_device" CHECK ("key_wraps"."kind" = 'device' or "key_wraps"."session_id" is null);--> statement-breakpoint
ALTER TABLE "key_links" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "key_links" FORCE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE POLICY tenant_isolation ON "key_links" FOR ALL
  USING (user_id = current_setting('app.user_id', true))
  WITH CHECK (user_id = current_setting('app.user_id', true));
