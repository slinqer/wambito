import { describe, expect, it, vi } from "vitest";
import { oneAtATime } from "./one-at-a-time.ts";

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}

describe("oneAtATime", () => {
  it("shares the open request instead of starting a second one", async () => {
    const answer = deferred<string>();
    const start = vi.fn(() => answer.promise);
    const requests = oneAtATime(start);
    const first = requests.run();
    const second = requests.run();
    expect(start).toHaveBeenCalledTimes(1);
    answer.resolve("picked");
    await expect(first).resolves.toBe("picked");
    await expect(second).resolves.toBe("picked");
  });

  it("starts a new request once the open one has ended", async () => {
    const start = vi.fn(async () => "picked");
    const requests = oneAtATime(start);
    await requests.run();
    await requests.run();
    expect(start).toHaveBeenCalledTimes(2);
  });

  it("starts a new request once the open one has failed", async () => {
    const start = vi.fn().mockRejectedValueOnce(new Error("aborted")).mockResolvedValue("picked");
    const requests = oneAtATime(start);
    await expect(requests.run()).rejects.toThrow("aborted");
    await expect(requests.run()).resolves.toBe("picked");
  });

  it("after forget, starts a new request even while the old one is open", async () => {
    const old = deferred<string>();
    const start = vi.fn().mockReturnValueOnce(old.promise).mockResolvedValue("fresh");
    const requests = oneAtATime(start);
    void requests.run();
    requests.forget();
    await expect(requests.run()).resolves.toBe("fresh");
    // the old request ending late does not clear the new one
    old.resolve("late");
    await Promise.resolve();
    expect(start).toHaveBeenCalledTimes(2);
  });
});
