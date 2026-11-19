export interface FieldError {
  path: string;
  message: string;
}

export interface ApiProblemInit {
  status: number;
  code: string;
  detail?: string | undefined;
  errors?: FieldError[] | undefined;
}

/**
 * A failed API call: the API's RFC 9457 problem. `code` is stable and drives the user-facing text
 * (`problemMessage`); `detail` and `errors` are for developers. Status 0 means no response at all.
 */
export class ApiProblem extends Error {
  readonly status: number;
  readonly code: string;
  readonly detail: string | undefined;
  readonly errors: FieldError[];

  constructor({ status, code, detail, errors }: ApiProblemInit) {
    super(detail ?? code);
    this.name = "ApiProblem";
    this.status = status;
    this.code = code;
    this.detail = detail;
    this.errors = errors ?? [];
  }
}

/** Reads a failed response into an `ApiProblem`, whatever the body looks like (proxies send HTML). */
export async function problemFromResponse(response: Response): Promise<ApiProblem> {
  let body: unknown;
  try {
    body = await response.json();
  } catch {
    body = undefined;
  }
  const fields = typeof body === "object" && body !== null ? (body as Record<string, unknown>) : {};
  // 426: this build predates the account's move to end-to-end encryption, whatever the body says.
  const code =
    response.status === 426
      ? "update_required"
      : typeof fields.code === "string" && fields.code
        ? fields.code
        : response.status >= 500
          ? "internal_error"
          : "http_error";
  return new ApiProblem({
    status: response.status,
    code,
    detail: typeof fields.detail === "string" ? fields.detail : undefined,
    errors: Array.isArray(fields.errors) ? (fields.errors as FieldError[]) : undefined,
  });
}

/**
 * What `useTranslations()` and `createTranslator()` both provide (the root, not a namespace). Their
 * keys are typed to the catalog; this accepts any string, since the key comes from the API's `code`.
 */
export type Translator = { translate(key: string): string }["translate"] & {
  has(key: string): boolean;
};

/** The text to show for a problem: `errors.<code>`, or `errors.generic` for a code we have no text for. */
export function problemMessage(problem: ApiProblem, t: Translator): string {
  const key = `errors.${problem.code}`;
  return t(t.has(key) ? key : "errors.generic");
}
