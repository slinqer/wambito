ALTER TABLE "session" ADD COLUMN "lifetime" text DEFAULT 'standard' NOT NULL;--> statement-breakpoint
ALTER TABLE "session" ADD CONSTRAINT "session_lifetime_check" CHECK ("session"."lifetime" in ('standard', 'long', 'short'));
