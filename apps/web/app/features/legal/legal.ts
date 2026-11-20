/** The sections of the privacy policy, in the order the page shows them. */
export const PRIVACY_SECTIONS = [
  "controller",
  "data",
  "purposes",
  "storage",
  "not_done",
  "voice",
  "capture",
  "assistants",
  "guest",
  "self_hosted",
  "rights",
  "changes",
] as const;

export type PrivacySection =
  | (typeof PRIVACY_SECTIONS)[number]
  | "analytics"
  | "not_done_with_analytics";

/**
 * The privacy policy's sections for a build. Without a PostHog key (self-hosted, dev, e2e) it is
 * `PRIVACY_SECTIONS`, whose "no analytics" stays true; with one, `analytics` follows `storage` and
 * `not_done_with_analytics` replaces `not_done`.
 */
export function privacySections(withAnalytics: boolean): readonly PrivacySection[] {
  if (!withAnalytics) return PRIVACY_SECTIONS;
  return PRIVACY_SECTIONS.flatMap((key): PrivacySection[] => {
    if (key === "storage") return [key, "analytics"];
    if (key === "not_done") return ["not_done_with_analytics"];
    return [key];
  });
}

// Provisional: Task 6's go-live checklist confirms these against the PostHog project before the key is set.
/** How long PostHog keeps landing events and session recordings, as the policy states it. */
export const ANALYTICS_RETENTION = { eventsMonths: 12, recordingsDays: 30 } as const;

/** The sections of the account deletion page, in order. */
export const DELETE_ACCOUNT_SECTIONS = ["in_app", "by_email", "what_goes", "backups"] as const;

export type LegalPageName = "privacy" | "deleteAccount";

/** Each page's namespace under `legal` in the site catalogs. */
export const LEGAL_MESSAGES = {
  privacy: "privacy",
  deleteAccount: "delete_account",
} as const satisfies Record<LegalPageName, string>;

/** The one address for privacy requests and account deletion by email. */
export const PRIVACY_EMAIL = "privacy@wambito.com";
