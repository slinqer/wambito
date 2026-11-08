export type CryptoErrorCode = "cannot_open" | "bad_recovery_key" | "bad_input";

export class CryptoError extends Error {
  readonly code: CryptoErrorCode;

  constructor(code: CryptoErrorCode, message?: string) {
    super(message ?? code);
    this.name = "CryptoError";
    this.code = code;
  }
}
