import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useSearchParams } from "react-router";
import { api, ApiError } from "../api";
import { ActionCard, DecidedCard } from "../components/ActionCard";
import { DismissDialog } from "../components/DismissDialog";
import { ReviewDialog } from "../components/ReviewDialog";
import { useToast } from "../components/Toasts";
import { KIND_LABEL, KIND_ORDER, recipient } from "../present";
import type { Center, Kind, ListName, Me, ProposedAction } from "../types";

type Decision =
  | { type: "approve"; action: ProposedAction; body: string }
  | { type: "dismiss"; action: ProposedAction; reason: string }
  | { type: "snooze"; action: ProposedAction; until: Date; label: string };

interface Props {
  me: Me;
  center: Center;
  list: ListName;
}

export function Queue({ me, center, list }: Props) {
  const client = useQueryClient();
  const toast = useToast();
  const [params, setParams] = useSearchParams();
  const [reviewing, setReviewing] = useState<ProposedAction | null>(null);
  const [dismissing, setDismissing] = useState<ProposedAction | null>(null);
  const [dialogError, setDialogError] = useState<string | null>(null);

  const key = ["actions", center.id, list] as const;
  const query = useQuery({ queryKey: key, queryFn: () => api.actions(center.id, list) });

  const decide = useMutation({
    mutationFn: (d: Decision) => {
      switch (d.type) {
        case "approve": return api.approve(center.id, d.action, d.body);
        case "dismiss": return api.dismiss(center.id, d.action, d.reason);
        case "snooze": return api.snooze(center.id, d.action, d.until);
      }
    },
    onSuccess: (_saved, d) => {
      client.setQueryData<ProposedAction[]>(key, (rows) => rows?.filter((r) => r.id !== d.action.id));
      setReviewing(null);
      setDismissing(null);
      toast(successText(d));
    },
    onError: (err, d) => {
      if (err instanceof ApiError && err.status === 401) {
        client.setQueryData(["me"], null);
      } else if (err instanceof ApiError && (err.status === 409 || err.status === 404)) {
        setReviewing(null);
        setDismissing(null);
        toast(err.status === 409 ? "Someone else already handled that one. Your list is up to date." : "That item is no longer available.", "warning");
      } else if (d.type === "snooze") {
        toast(err.message, "warning");
      } else {
        setDialogError(err instanceof ApiError ? err.message : "Couldn't save. Check your connection and try again.");
      }
    },
    onSettled: () => client.invalidateQueries({ queryKey: ["actions", center.id] }),
  });

  const busyId = decide.isPending ? decide.variables?.action.id : undefined;
  const rows = query.data ?? [];
  const kindParam = params.get("kind");
  const kindFilter = KIND_ORDER.find((k) => k === kindParam) ?? null;

  if (query.isPending) return <SkeletonList />;
  if (query.isError) {
    return (
      <div className="empty" role="alert">
        <h2>Couldn't load this list</h2>
        <p className="muted">{query.error.message}</p>
        <button type="button" className="button button--quiet" onClick={() => query.refetch()}>Try again</button>
      </div>
    );
  }

  if (list !== "inbox") {
    return rows.length === 0 ? (
      <div className="empty">
        <h2>{list === "approved" ? "Nothing approved yet" : "Nothing dismissed"}</h2>
        <p className="muted">{list === "approved" ? "Messages you approve land here." : "Items you dismiss land here with your reason."}</p>
      </div>
    ) : (
      <div className="stack">{rows.map((a) => <DecidedCard key={a.id} action={a} />)}</div>
    );
  }

  const counts = KIND_ORDER.map((k) => [k, rows.filter((r) => r.kind === k).length] as const);
  const visible = kindFilter ? rows.filter((r) => r.kind === kindFilter) : rows;

  const setKind = (k: Kind | null) => {
    const next = new URLSearchParams(params);
    if (k) next.set("kind", k);
    else next.delete("kind");
    setParams(next, { replace: true });
  };

  return (
    <>
      {rows.length > 0 && (
        <div className="filters" role="group" aria-label="Filter by type">
          <button type="button" className="chip" aria-pressed={!kindFilter} onClick={() => setKind(null)}>
            All <span className="chip__count">{rows.length}</span>
          </button>
          {counts.map(([k, n]) => n > 0 && (
            <button key={k} type="button" className={`chip chip--${k}`} aria-pressed={kindFilter === k} onClick={() => setKind(k)}>
              {KIND_LABEL[k]} <span className="chip__count">{n}</span>
            </button>
          ))}
        </div>
      )}

      {visible.length === 0 ? (
        <div className="empty">
          <h2>All clear</h2>
          <p className="muted">Nothing needs you right now. Cubby checks again overnight.</p>
        </div>
      ) : (
        KIND_ORDER.map((k) => {
          const group = visible.filter((r) => r.kind === k);
          if (group.length === 0) return null;
          return (
            <section key={k} className="group" aria-labelledby={`group-${k}`}>
              <h2 id={`group-${k}`} className="group__title">{KIND_LABEL[k]} <span className="muted">{group.length}</span></h2>
              <div className="stack">
                {group.map((a) => (
                  <ActionCard
                    key={a.id}
                    action={a}
                    busy={busyId === a.id}
                    onReview={(x) => { setDialogError(null); setReviewing(x); }}
                    onDismiss={(x) => { setDialogError(null); setDismissing(x); }}
                    onSnooze={(x, until, label) => decide.mutate({ type: "snooze", action: x, until, label })}
                  />
                ))}
              </div>
            </section>
          );
        })
      )}

      {reviewing && (
        <ReviewDialog
          action={reviewing}
          directorName={me.user.name}
          centerName={center.name}
          pending={decide.isPending}
          error={dialogError}
          onApprove={(body) => decide.mutate({ type: "approve", action: reviewing, body })}
          onClose={() => setReviewing(null)}
        />
      )}
      {dismissing && (
        <DismissDialog
          action={dismissing}
          pending={decide.isPending}
          error={dialogError}
          onDismiss={(reason) => decide.mutate({ type: "dismiss", action: dismissing, reason })}
          onClose={() => setDismissing(null)}
        />
      )}
    </>
  );
}

function successText(d: Decision): string {
  switch (d.type) {
    case "approve": {
      const to = recipient(d.action);
      return to ? `Approved. The message to ${to} is ready to send.` : "Marked as handled.";
    }
    case "dismiss": return "Dismissed.";
    case "snooze":
      return `Snoozed until ${d.until.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" })}.`;
  }
}

function SkeletonList() {
  return (
    <div className="stack" aria-busy="true" aria-label="Loading">
      {[0, 1, 2].map((i) => <div key={i} className="card skeleton" />)}
    </div>
  );
}
