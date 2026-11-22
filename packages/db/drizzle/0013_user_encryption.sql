ALTER TABLE "user" ADD COLUMN "encryption" text DEFAULT 'plain' NOT NULL;--> statement-breakpoint
ALTER TABLE "user" ADD COLUMN "platform" text;--> statement-breakpoint
ALTER TABLE "user" ADD CONSTRAINT "user_encryption_check" CHECK ("user"."encryption" in ('plain', 'encrypted'));--> statement-breakpoint
ALTER TABLE "user" ADD CONSTRAINT "user_platform_check" CHECK ("user"."platform" in ('android', 'ios', 'web'));
