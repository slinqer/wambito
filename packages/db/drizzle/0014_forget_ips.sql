-- No IP address is stored (spec 2026-11-15 section 9): rate limits live in memory, sessions keep
-- no address. Forget what the old code wrote.
DELETE FROM "rate_limit";--> statement-breakpoint
UPDATE "session" SET "ip_address" = NULL;
