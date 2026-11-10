import { useEffect, useId, useRef, useState } from "react";
import { useTranslations } from "use-intl";
import {
  type ApproverPairing,
  findPairing as findRealPairing,
  type PairingOptions,
} from "../../local/pairing.ts";
import { cx } from "../../ui/cx.ts";
import { PressButton } from "../../ui/PressButton.tsx";
import { FieldError, ScreenTitle, SignInScreen } from "../sign-in/SignInScreen.tsx";
import { PairingNumber, type PairingProblem, pairingProblem } from "./PairNewDevice.tsx";

/** The part of the browser's `BarcodeDetector` the scan uses (Chromium only, no TS types yet). */
interface BarcodeDetectorLike {
  detect(source: HTMLVideoElement): Promise<{ rawValue: string }[]>;
}
type BarcodeDetectorClass = new (options: { formats: string[] }) => BarcodeDetectorLike;

const barcodeDetector = (): BarcodeDetectorClass | undefined =>
  (globalThis as { BarcodeDetector?: BarcodeDetectorClass }).BarcodeDetector;

/** Scanning needs `BarcodeDetector` (Chromium); elsewhere the typed code is the way. */
const browserCanScan = () => typeof barcodeDetector() !== "undefined";

const SCAN_EVERY_MS = 250;
const PAIR_QR = "wambito://pair?";

export interface ApproveDeviceProps {
  /** This browser's vault (`userId`, and `fetch`/`clock` in tests): DK comes from its device wrap. */
  keys: PairingOptions;
  /** `local/pairing.ts` `findPairing`; stories pass a fake one. */
  findPairing?: (
    options: PairingOptions & ({ code: string } | { qr: string }),
  ) => Promise<ApproverPairing>;
  /** Whether this browser can scan a QR (`BarcodeDetector`); stories stand in for it. */
  scanSupported?(): boolean;
  /** Closes the screen: done, nothing shared, or given up. */
  onDone(): void;
}

type View =
  | { step: "enter"; error: "bad_code" | null; busy: boolean }
  | { step: "scan" }
  | { step: "waiting"; pairing: ApproverPairing }
  | { step: "number"; pairing: ApproverPairing; number: string; approving: boolean }
  | { step: "done" }
  | { step: "mismatch" }
  | { step: "failed"; problem: PairingProblem };

/**
 * An unlocked device approves a new one: type the code it shows (or scan its QR where the browser
 * can), compare the number on both screens, then "They match" seals the data key to it. "They do
 * not match" cancels: nothing was shared. "They match" exists only once the number is shown.
 */
export function ApproveDevice({
  keys,
  findPairing = findRealPairing,
  scanSupported = browserCanScan,
  onDone,
}: ApproveDeviceProps) {
  const t = useTranslations("vault.approve");
  const [view, setView] = useState<View>({ step: "enter", error: null, busy: false });
  const [code, setCode] = useState("");
  const [cameraFailed, setCameraFailed] = useState(false);
  const [canScan] = useState(() => scanSupported());
  const inputId = useId();
  const errorId = useId();
  const alertId = useId();
  /** The pairing in progress, cancelled when the screen goes away before it is done. */
  const current = useRef<ApproverPairing | null>(null);
  const mounted = useRef(true);

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      current.current?.cancel();
      current.current = null;
    };
  }, []);

  const fail = (pairing: ApproverPairing | null, error: unknown) => {
    if (pairing && current.current !== pairing) return;
    const problem = pairingProblem(error);
    if (problem === null) return;
    if (problem === "bad_code") {
      setView({ step: "enter", error: "bad_code", busy: false });
      return;
    }
    pairing?.cancel();
    current.current = null;
    setView({ step: "failed", problem });
  };

  async function find(input: { code: string } | { qr: string }) {
    setView({ step: "enter", error: null, busy: true });
    let pairing: ApproverPairing;
    try {
      pairing = await findPairing({ ...keys, ...input });
    } catch (error) {
      if (mounted.current) fail(null, error);
      return;
    }
    if (!mounted.current) {
      pairing.cancel();
      return;
    }
    current.current = pairing;
    setView({ step: "waiting", pairing });
    try {
      const number = await pairing.number();
      if (current.current === pairing) {
        setView({ step: "number", pairing, number, approving: false });
      }
    } catch (error) {
      fail(pairing, error);
    }
  }

  async function approve(pairing: ApproverPairing, number: string) {
    setView({ step: "number", pairing, number, approving: true });
    try {
      await pairing.approve();
    } catch (error) {
      fail(pairing, error);
      return;
    }
    if (current.current !== pairing) return;
    current.current = null;
    setView({ step: "done" });
  }

  const giveUp = () => {
    current.current?.cancel();
    current.current = null;
    onDone();
  };

  const startAgain = () => {
    setCode("");
    setView({ step: "enter", error: null, busy: false });
  };

  if (view.step === "done" || view.step === "mismatch") {
    const done = view.step === "done";
    return (
      <SignInScreen mood={done ? "celebrating" : "worried"}>
        <ScreenTitle>{t(done ? "done_title" : "mismatch_title")}</ScreenTitle>
        <p className="text-center text-ink-muted">{t(done ? "done_lead" : "mismatch_lead")}</p>
        <PressButton className="w-full" onClick={onDone}>
          {t("close")}
        </PressButton>
      </SignInScreen>
    );
  }

  if (view.step === "failed") {
    const { problem } = view;
    return (
      <SignInScreen mood="worried">
        <ScreenTitle>{t(problem === "expired" ? "expired_title" : "failed_title")}</ScreenTitle>
        {problem === "expired" ? (
          <p className="text-center text-ink-muted">{t("expired_lead")}</p>
        ) : (
          <FieldError id={alertId}>{t(problem)}</FieldError>
        )}
        {problem !== "tampered" && (
          <PressButton className="w-full" onClick={startAgain}>
            {t("restart")}
          </PressButton>
        )}
        <PressButton
          variant={problem === "tampered" ? "primary" : "ghost"}
          className="w-full"
          onClick={onDone}
        >
          {t("close")}
        </PressButton>
      </SignInScreen>
    );
  }

  if (view.step === "waiting" || view.step === "number") {
    return (
      <SignInScreen>
        <ScreenTitle>{t("title")}</ScreenTitle>
        {view.step === "waiting" ? (
          <p className="text-center text-ink-muted" role="status">
            {t("waiting")}
          </p>
        ) : (
          <>
            <h2 className="m-0 text-center text-[18px] font-bold text-ink">{t("number_title")}</h2>
            <PairingNumber value={view.number} />
            <p className="text-center text-ink-muted">{t("number_lead")}</p>
            <PressButton
              className="w-full"
              disabled={view.approving}
              aria-busy={view.approving || undefined}
              onClick={() => {
                if (!view.approving) void approve(view.pairing, view.number);
              }}
            >
              {view.approving ? t("approving") : t("match")}
            </PressButton>
            <PressButton
              variant="secondary"
              className="w-full"
              disabled={view.approving}
              onClick={() => {
                view.pairing.cancel();
                current.current = null;
                setView({ step: "mismatch" });
              }}
            >
              {t("no_match")}
            </PressButton>
          </>
        )}
        {view.step === "waiting" && (
          <PressButton variant="ghost" className="w-full" onClick={giveUp}>
            {t("cancel")}
          </PressButton>
        )}
      </SignInScreen>
    );
  }

  const busy = view.step === "enter" && view.busy;
  const error = view.step === "enter" ? view.error : null;
  return (
    <SignInScreen>
      <ScreenTitle>{t("title")}</ScreenTitle>
      <p className="text-center text-ink-muted">{t("lead")}</p>
      {view.step === "scan" ? (
        <div className="flex w-full flex-col gap-(--space-2)">
          <p className="text-center text-ink-muted">{t("scan_lead")}</p>
          <QrScanner
            onScan={(qr) => void find({ qr })}
            onFail={() => {
              setCameraFailed(true);
              setView({ step: "enter", error: null, busy: false });
            }}
          />
          <PressButton
            variant="secondary"
            className="w-full"
            onClick={() => setView({ step: "enter", error: null, busy: false })}
          >
            {t("scan_stop")}
          </PressButton>
        </div>
      ) : (
        <form
          noValidate
          className="flex w-full flex-col gap-(--space-3)"
          onSubmit={(event) => {
            event.preventDefault();
            if (!busy && code.trim() !== "") void find({ code });
          }}
        >
          <label htmlFor={inputId} className="text-sm text-ink-muted">
            {t("code_label")}
          </label>
          <div className={cx("lk-input min-h-11", error && "border-over")}>
            <input
              id={inputId}
              name="pairing-code"
              type="text"
              autoComplete="off"
              autoCapitalize="characters"
              autoCorrect="off"
              spellCheck={false}
              translate="no"
              placeholder={t("placeholder")}
              value={code}
              onChange={(event) => {
                setCode(event.target.value);
                if (error) setView({ step: "enter", error: null, busy: false });
              }}
              aria-invalid={error !== null || undefined}
              aria-describedby={error ? errorId : undefined}
              className="min-h-9 min-w-0 flex-1 border-0 bg-transparent p-0 font-mono text-[16px] text-ink uppercase outline-none placeholder:font-normal placeholder:text-ink-muted"
            />
          </div>
          {error && <FieldError id={errorId}>{t(`error_${error}`)}</FieldError>}
          <PressButton type="submit" className="w-full" disabled={busy || code.trim() === ""}>
            {busy ? t("finding") : t("submit")}
          </PressButton>
        </form>
      )}
      {canScan && view.step === "enter" && (
        <div className="flex w-full flex-col gap-(--space-2)">
          <PressButton
            variant="secondary"
            className="w-full"
            disabled={busy}
            onClick={() => {
              setCameraFailed(false);
              setView({ step: "scan" });
            }}
          >
            {t("scan")}
          </PressButton>
          {cameraFailed && <FieldError id={alertId}>{t("camera_failed")}</FieldError>}
        </div>
      )}
      <PressButton variant="ghost" className="w-full" disabled={busy} onClick={giveUp}>
        {t("cancel")}
      </PressButton>
    </SignInScreen>
  );
}

/**
 * The camera, scanning for a `wambito://pair?` QR with `BarcodeDetector`. The stream stops on a
 * hit, on unmount (cancel), and when the camera cannot start (`onFail`).
 */
function QrScanner({ onScan, onFail }: { onScan(qr: string): void; onFail(): void }) {
  const video = useRef<HTMLVideoElement>(null);
  const callbacks = useRef({ onScan, onFail });
  callbacks.current = { onScan, onFail };

  useEffect(() => {
    let alive = true;
    let stream: MediaStream | null = null;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const stop = () => {
      clearTimeout(timer);
      for (const track of stream?.getTracks() ?? []) track.stop();
      stream = null;
    };
    void (async () => {
      const Detector = barcodeDetector();
      const element = video.current;
      try {
        if (!Detector || !element) throw new Error("no_scanner");
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "environment" },
          audio: false,
        });
        if (!alive) return stop();
        element.srcObject = stream;
        await element.play();
        const detector = new Detector({ formats: ["qr_code"] });
        const tick = async () => {
          if (!alive) return;
          try {
            const found = await detector.detect(element);
            const hit = found.find((code) => code.rawValue.startsWith(PAIR_QR));
            if (hit && alive) {
              stop();
              callbacks.current.onScan(hit.rawValue);
              return;
            }
          } catch {
            // A frame that cannot be read yet: try the next one.
          }
          if (alive) timer = setTimeout(() => void tick(), SCAN_EVERY_MS);
        };
        void tick();
      } catch {
        stop();
        if (alive) callbacks.current.onFail();
      }
    })();
    return () => {
      alive = false;
      stop();
    };
  }, []);

  return (
    <video
      ref={video}
      muted
      playsInline
      className="aspect-square w-full rounded-(--radius-md) bg-black object-cover"
    />
  );
}
