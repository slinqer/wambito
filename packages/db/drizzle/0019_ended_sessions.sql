CREATE TABLE "deleted_users" (
	"user_hash" "bytea" PRIMARY KEY NOT NULL,
	"deleted_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "deleted_users_user_hash_len" CHECK (octet_length("deleted_users"."user_hash") = 32)
);
--> statement-breakpoint
CREATE TABLE "ended_sessions" (
	"session_hash" "bytea" PRIMARY KEY NOT NULL,
	"reason" text NOT NULL,
	"ended_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "ended_sessions_session_hash_len" CHECK (octet_length("ended_sessions"."session_hash") = 32),
	CONSTRAINT "ended_sessions_reason" CHECK ("ended_sessions"."reason" = 'device_removed')
);
