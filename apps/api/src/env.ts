export interface SessionUser {
  id: string;
  email: string;
  timezone: string;
  locale: string;
}

/**
 * How the request was let in: the person's own session (the app or the web), or an assistant's
 * OAuth access token, which carries the client and the scopes the person granted it.
 */
export type Grant =
  | { kind: "session"; sessionId: string }
  | { kind: "oauth"; clientId: string; scopes: string[] };

export interface AppEnv {
  Variables: {
    userId: string;
    user: SessionUser;
    grant: Grant;
  };
}

/** What `requireAdmin` (http/admin.ts) adds for the `/v1/admin/*` routes. */
export interface AdminEnv {
  Variables: {
    /** The signed-in admin's user id. */
    adminId: string;
    /** The admin's session, which a passkey verification belongs to. */
    sessionId: string;
    /** When the session's passkey verification was made; `null` on the verification routes. */
    adminVerifiedAt: Date | null;
  };
}
