import { KIND_LABEL, facts, languageName, timeAgo, title } from "../present";
import type { ProposedAction } from "../types";
import { SnoozeMenu } from "./SnoozeMenu";

interface Props {
  action: ProposedAction;
  busy: boolean;
  onReview: (a: ProposedAction) => void;
  onDismiss: (a: ProposedAction) => void;
  onSnooze: (a: ProposedAction, until: Date, label: string) => void;
}

export function ActionCard({ action, busy, onReview, onDismiss, onSnooze }: Props) {
  const lang = action.kind === "ratio_risk" ? null : languageName(action.facts.preferred_language);
  const headingId = `action-${action.id}-title`;

  return (
    <article className={`card card--${action.kind}`} aria-labelledby={headingId} aria-busy={busy}>
      <div className="card__meta">
        <span className={`badge badge--${action.kind}`}>{KIND_LABEL[action.kind]}</span>
        <span className="muted">Found {timeAgo(action.detected_at)}</span>
      </div>
      <h3 id={headingId} className="card__title">{title(action)}</h3>
      <p className="card__rationale">{action.rationale}</p>
      <dl className="facts">
        {facts(action).map((f) => (
          <div key={f.label} className="facts__item">
            <dt>{f.label}</dt>
            <dd>{f.value}</dd>
          </div>
        ))}
      </dl>
      {lang && <p className="hint">Family prefers {lang}</p>}
      <div className="card__actions">
        <button type="button" className="button button--primary" disabled={busy} onClick={() => onReview(action)}>
          {action.family_facing ? "Review message" : "Mark handled"}
        </button>
        <SnoozeMenu disabled={busy} onPick={(until, label) => onSnooze(action, until, label)} />
        <button type="button" className="button button--quiet" disabled={busy} onClick={() => onDismiss(action)}>
          Dismiss
        </button>
      </div>
    </article>
  );
}

export function DecidedCard({ action }: { action: ProposedAction }) {
  const who = action.decided_by_name ?? "Someone";
  const when = action.decided_at ? timeAgo(action.decided_at) : "";
  return (
    <article className={`card card--decided card--${action.kind}`}>
      <div className="card__meta">
        <span className={`badge badge--${action.kind}`}>{KIND_LABEL[action.kind]}</span>
        <span className="muted">
          {action.status === "approved" ? "Approved" : "Dismissed"} by {who} · {when}
        </span>
      </div>
      <h3 className="card__title">{title(action)}</h3>
      {action.status === "approved" && action.final_body && (
        <blockquote className="message-preview">{action.final_body}</blockquote>
      )}
      {action.status === "approved" && !action.final_body && <p className="muted">Marked as handled.</p>}
      {action.status === "dismissed" && (
        <p className="muted">{action.dismiss_reason ? `Reason: ${action.dismiss_reason}` : "No reason given."}</p>
      )}
      {action.status === "approved" && action.final_body && <span className="pill">Ready to send</span>}
    </article>
  );
}
