CREATE TABLE "activity_daily" (
	"day" date NOT NULL,
	"platform" text NOT NULL,
	"app_version" text DEFAULT '' NOT NULL,
	"cohort_week" date NOT NULL,
	"has_email" boolean NOT NULL,
	"count" integer NOT NULL,
	CONSTRAINT "activity_daily_day_platform_app_version_cohort_week_has_email_pk" PRIMARY KEY("day","platform","app_version","cohort_week","has_email")
);
--> statement-breakpoint
ALTER TABLE "user" ADD COLUMN "app_version" text;--> statement-breakpoint
ALTER TABLE "user" ADD COLUMN "last_seen_day" text;