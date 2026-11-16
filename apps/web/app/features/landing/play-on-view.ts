import { useEffect, useRef, useState } from "react";

/**
 * A landing illustration that plays on a loop, for one or several examples that take turns: while
 * at least `threshold` of it is on screen, it plays example `index`'s steps (each at its delay, ms
 * after the round starts; `idle`, empty, before the first), holds the last one for
 * `hold` ms, then moves on to the next example (or replays the only one) and plays again, round and
 * round, so the illustration stays alive for someone who keeps looking.
 * Scrolled away it stops where it is, and scrolling back plays the next one. It starts and stays on
 * the first example, `done`, before hydration, without IntersectionObserver and under reduced
 * motion. `pace` scales every delay (stories run it fast; the page uses 1).
 */
export function useRotatingPlay<Step extends string>(
  count: number,
  steps: readonly (readonly [Step, number])[],
  hold: number,
  { pace = 1, threshold = 0.5 }: { pace?: number; threshold?: number } = {},
) {
  const ref = useRef<HTMLDivElement>(null);
  const [state, setState] = useState<{ index: number; phase: Step | "idle" | "done" }>({
    index: 0,
    phase: "done",
  });
  const timeline = useRef(steps);
  useEffect(() => {
    const el = ref.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    setState({ index: 0, phase: "idle" });
    let timers: number[] = [];
    let current = 0;
    let started = false;
    const stop = () => {
      for (const timer of timers) window.clearTimeout(timer);
      timers = [];
    };
    const play = (index: number) => {
      stop();
      current = index;
      setState({ index, phase: "idle" });
      let last = 0;
      for (const [step, delay] of timeline.current) {
        last = Math.max(last, delay);
        timers.push(window.setTimeout(() => setState({ index, phase: step }), delay * pace));
      }
      timers.push(window.setTimeout(() => play((index + 1) % count), (last + hold) * pace));
    };
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry?.isIntersecting) {
          play(started ? (current + 1) % count : 0);
          started = true;
        } else {
          stop();
        }
      },
      { threshold },
    );
    observer.observe(el);
    return () => {
      observer.disconnect();
      stop();
    };
  }, [count, hold, pace, threshold]);
  return { ref, ...state };
}

/**
 * A card illustration that replays by itself: each time at least `threshold` of the element comes
 * on screen `round` goes up, and again every `every` ms while it stays there (scaled by `pace`).
 * Key the illustration on `round` so its CSS animations restart. `round` stays 0 (the still, final
 * picture) before hydration, without IntersectionObserver and under reduced motion.
 */
export function useReplayOnView<T extends HTMLElement>(
  every: number,
  { pace = 1, threshold = 0.5 }: { pace?: number; threshold?: number } = {},
) {
  const ref = useRef<T>(null);
  const [round, setRound] = useState(0);
  useEffect(() => {
    const el = ref.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    let timer: number | undefined;
    const stop = () => window.clearInterval(timer);
    const observer = new IntersectionObserver(
      ([entry]) => {
        stop();
        if (!entry?.isIntersecting) return;
        setRound((n) => n + 1);
        timer = window.setInterval(() => setRound((n) => n + 1), every * pace);
      },
      { threshold },
    );
    observer.observe(el);
    return () => {
      observer.disconnect();
      stop();
    };
  }, [every, pace, threshold]);
  return { ref, round };
}
