import type { Hook } from "@hono/zod-openapi";
import type { Context } from "hono";
import { HTTPException } from "hono/http-exception";
import type { ContentfulStatusCode } from "hono/utils/http-status";

export interface FieldError {
  path: string;
  message: string;
}

/** An error rendered as RFC 9457 problem+json with a stable `code`. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly detail?: string,
    readonly errors?: FieldError[],
  ) {
    super(detail ?? code);
    this.name = "ApiError";
  }
}

const TITLES: Record<number, string> = {
  400: "Bad Request",
  401: "Unauthorized",
  403: "Forbidden",
  404: "Not Found",
  409: "Conflict",
  410: "Gone",
  413: "Payload Too Large",
  422: "Unprocessable Content",
  429: "Too Many Requests",
  500: "Internal Server Error",
};

export function problem(c: Context, error: ApiError): Response {
  const body = {
    type: "about:blank",
    title: TITLES[error.status] ?? "Error",
    status: error.status,
    code: error.code,
    ...(error.detail ? { detail: error.detail } : {}),
    ...(error.errors ? { errors: error.errors } : {}),
  };
  return c.body(JSON.stringify(body), error.status as ContentfulStatusCode, {
    "content-type": "application/problem+json",
  });
}

/**
 * What may be logged of an unexpected error. A Drizzle query error carries the statement's bound
 * `params` (opaque encrypted bytes, keys, commitments) in its `message`, `query`, `params`, and
 * `cause`; those are never logged, only the error's name, the Postgres code and the first line
 * of the message before the parameters.
 */
export function safeLogFields(err: unknown): unknown {
  const params = (err as { params?: unknown } | null)?.params;
  const isQueryError =
    err instanceof Error && (err.name === "DrizzleQueryError" || Array.isArray(params));
  if (!isQueryError) return err;
  const cause = (err as { cause?: { code?: unknown; name?: unknown } }).cause;
  return {
    name: err.name,
    message: "database query failed",
    code: typeof cause?.code === "string" ? cause.code : undefined,
    causeName: typeof cause?.name === "string" ? cause.name : undefined,
  };
}

export function onError(err: Error, c: Context): Response {
  if (err instanceof ApiError) return problem(c, err);
  if (err instanceof HTTPException) {
    return problem(
      c,
      new ApiError(err.status, err.status === 400 ? "bad_request" : "http_error", err.message),
    );
  }
  console.error(safeLogFields(err));
  return problem(c, new ApiError(500, "internal_error"));
}

export function notFound(c: Context): Response {
  return problem(c, new ApiError(404, "not_found"));
}

/** `@hono/zod-openapi` hook: turns validation failures into 422 `validation_failed`. */
export const validationHook: Hook<unknown, any, any, unknown> = (result) => {
  if (!result.success) {
    throw new ApiError(
      422,
      "validation_failed",
      "The request is invalid",
      result.error.issues.map((issue) => ({ path: issue.path.join("."), message: issue.message })),
    );
  }
};
