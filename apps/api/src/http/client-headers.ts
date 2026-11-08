/**
 * The headers the web and the app send about the client: the page's language (`locale`), where to
 * go after signing in (`next`), the device's time zone (`timezone`), `client: android`, and
 * `background: 1` for jobs the person did not start, and `user`: the account a `/v2` call means (a
 * tab whose cookie now belongs to someone else gets 409 `session_changed`).
 */
export type ClientHeaderName = "locale" | "next" | "timezone" | "client" | "background" | "user";

/** A client header: `x-wambito-<name>`. */
export function clientHeader(
  headers: Headers | undefined,
  name: ClientHeaderName,
): string | undefined {
  return headers?.get(`x-wambito-${name}`) ?? undefined;
}
