import { useCallback, useEffect, useState } from "react";
import { useTranslations } from "use-intl";
import { PressButton } from "../ui/PressButton.tsx";
import { ActivityBlocks } from "./ActivityBlocks.tsx";
import { type AuditEntry, AuditList } from "./AuditList.tsx";
import { LookupBox } from "./LookupBox.tsx";
import { type AdminMetrics, MetricCards } from "./MetricCards.tsx";
import { SignupsChart } from "./SignupsChart.tsx";
import { useAdmin } from "./use-admin.ts";

type Metrics =
  | { status: "loading" }
  | { status: "error" }
  | { status: "ready"; data: AdminMetrics };

interface Audit {
  entries: AuditEntry[];
  next: string | null;
  loadingMore: boolean;
  moreFailed: boolean;
}

/**
 * `/admin` (spec §6), in this order: the user counts, the weekly sign-ups chart, the activity
 * blocks (daily actives, cohorts, installs, versions), the suspended count, the 50 latest audit rows (with "Load more") and the look-up box. Every call goes through
 * `adminFetch`, so a stale passkey verification parks it until the admin confirms again.
 */
export function HomeScreen() {
  const t = useTranslations("admin.home");
  const admin = useAdmin();
  const { adminFetch, client } = admin;
  const [metrics, setMetrics] = useState<Metrics>({ status: "loading" });
  const [audit, setAudit] = useState<Audit | null>(null);

  const loadMetrics = useCallback(() => {
    setMetrics({ status: "loading" });
    adminFetch(() => client.GET("/v1/admin/metrics")).then(
      ({ data }) => setMetrics(data ? { status: "ready", data } : { status: "error" }),
      () => setMetrics({ status: "error" }),
    );
  }, [adminFetch, client]);

  useEffect(() => {
    loadMetrics();
    let live = true;
    adminFetch(() => client.GET("/v1/admin/audit")).then(
      ({ data }) => {
        if (live && data) setAudit({ ...data, loadingMore: false, moreFailed: false });
      },
      () => {},
    );
    return () => {
      live = false;
    };
  }, [adminFetch, client, loadMetrics]);

  function loadMore() {
    if (!audit?.next) return;
    const before = audit.next;
    setAudit({ ...audit, loadingMore: true, moreFailed: false });
    adminFetch(() => client.GET("/v1/admin/audit", { params: { query: { before } } })).then(
      ({ data }) =>
        setAudit((now) =>
          now && data
            ? {
                entries: [...now.entries, ...data.entries],
                next: data.next,
                loadingMore: false,
                moreFailed: false,
              }
            : now,
        ),
      () => setAudit((now) => (now ? { ...now, loadingMore: false, moreFailed: true } : now)),
    );
  }

  return (
    <main className="lk-screen min-h-dvh">
      <div className="mx-auto flex w-full max-w-[720px] flex-col gap-(--space-4) px-(--space-4) py-(--space-5)">
        <h1 className="m-0 font-display text-[28px] leading-tight font-bold text-ink">
          {t("title")}
        </h1>
        {metrics.status === "loading" && (
          <p role="status" className="m-0 text-ink-muted">
            {t("loading")}
          </p>
        )}
        {metrics.status === "error" && (
          <div className="flex flex-col items-start gap-(--space-3)">
            <p role="alert" className="m-0 text-over">
              {t("error")}
            </p>
            <PressButton variant="secondary" onClick={loadMetrics}>
              {t("retry")}
            </PressButton>
          </div>
        )}
        {metrics.status === "ready" && (
          <>
            <MetricCards metrics={metrics.data} />
            <SignupsChart weekly={metrics.data.weekly} />
            <ActivityBlocks metrics={metrics.data} />
            <p className="m-0 font-bold text-ink">
              {t("suspended", { count: metrics.data.suspended })}
            </p>
          </>
        )}
        {audit && (
          <AuditList
            entries={audit.entries}
            hasMore={audit.next !== null}
            loadingMore={audit.loadingMore}
            moreFailed={audit.moreFailed}
            onMore={loadMore}
          />
        )}
        <LookupBox />
      </div>
    </main>
  );
}
