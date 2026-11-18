/**
 * One request open at a time: `run` hands back the open request when there is one, and starts a
 * new one otherwise. The sign-in page's conditional passkey request needs it: the server keeps one
 * challenge per browser (a cookie), so a second request started while the first is open replaces
 * the first one's challenge, and a passkey picked for the first then fails to verify. `forget`
 * is for when the open request was ended elsewhere (an explicit passkey request aborts it).
 */
export function oneAtATime<T>(start: () => Promise<T>): { run(): Promise<T>; forget(): void } {
  let open: Promise<T> | null = null;
  return {
    run() {
      if (open) return open;
      const mine: Promise<T> = start().finally(() => {
        if (open === mine) open = null;
      });
      open = mine;
      return mine;
    },
    forget() {
      open = null;
    },
  };
}
