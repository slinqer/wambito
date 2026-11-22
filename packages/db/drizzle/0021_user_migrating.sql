ALTER TABLE "user" ADD COLUMN "migration_session_id" text;--> statement-breakpoint
ALTER TABLE "user" DROP CONSTRAINT "user_encryption_check";--> statement-breakpoint
ALTER TABLE "user" ADD CONSTRAINT "user_encryption_check" CHECK ("user"."encryption" in ('plain', 'migrating', 'encrypted'));
