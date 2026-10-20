import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { api } from "../api";
import { languageName, recipient, shortDay, starterMessage } from "../present";
import type { ProposedAction } from "../types";
import { Modal } from "./Modal";

const MAX = 5000;

interface Props {
  action: ProposedAction;
  directorName: string;
  centerName: string;
  pending: boolean;
  error: string | null;
  onApprove: (body: string) => void;
  onClose: () => void;
}

export function ReviewDialog(props: Props) {
  return props.action.family_facing ? <MessageDialog {...props} /> : <HandledDialog {...props} />;
}

function MessageDialog({ action, directorName, centerName, pending, error, onApprove, onClose }: Props) {
  const drafted = action.draft_status === "ready" && Boolean(action.draft_body);
  const [body, setBody] = useState(() => (drafted && action.draft_body) || starterMessage(action, directorName, centerName));
  const lang = action.kind === "ratio_risk" ? null : languageName(action.facts.preferred_language);
  const blank = body.trim() === "";
  const tooLong = body.length > MAX;

  return (
    <Modal
      variant="drawer"
      title={`Message to ${recipient(action)}`}
      description={action.rationale}
      onClose={onClose}
      footer={
        <>
          <button type="button" className="button button--quiet" onClick={onClose}>Cancel</button>
          <button
            type="button"
            className="button button--primary"
            disabled={pending || blank || tooLong}
            onClick={() => onApprove(body)}
          >
            {pending ? "Approving…" : "Approve message"}
          </button>
        </>
      }
    >
      <label className="field">
        <span className="field__label">Message</span>
        <textarea
          data-autofocus
          className="field__input field__input--message"
          value={body}
          onChange={(e) => setBody(e.target.value)}
          rows={14}
          aria-describedby="message-help"
          aria-invalid={blank || tooLong}
        />
      </label>
      <div id="message-help" className="field__help">
        <span>Edit anything before you approve.{lang ? ` The family prefers ${lang}.` : ""}</span>
        <span className={tooLong ? "danger" : undefined}>{body.length.toLocaleString()} / {MAX.toLocaleString()}</span>
      </div>
      <DraftSource action={action} />
      {error && <p className="form-error" role="alert">{error}</p>}
    </Modal>
  );
}

function DraftSource({ action }: { action: ProposedAction }) {
  const latest = useQuery({ queryKey: ["eval", "latest"], queryFn: api.latestEval, staleTime: 10 * 60_000 });
  const run = latest.data;

  let note: string;
  switch (action.draft_status) {
    case "ready":
      note = "Drafted by Claude from this item's facts and the center handbook. Cubby checked the amounts, names, and citations.";
      break;
    case "pending":
      note = "Claude is still drafting this one, so this is Cubby's plain starting text. Reopen in a moment to see the draft.";
      break;
    case "failed":
      note = "Claude's draft didn't pass Cubby's checks, so this is plain starting text built from the facts.";
      break;
    default:
      note = "Plain starting text built from this item's facts.";
  }

  return (
    <aside className="draft-source" aria-label="About this draft">
      <p>{note}</p>
      {action.draft_status === "ready" && action.draft_citations.length > 0 && (
        <p>
          <span className="draft-source__label">Based on</span>{" "}
          {action.draft_citations.map((c) => c.heading).join(" · ")}
        </p>
      )}
      {run && run.checks_total > 0 && (
        <p className="muted">
          Latest draft eval: {run.checks_passed}/{run.checks_total} checks passed
          {run.judge_score ? `, tone and clarity ${Number(run.judge_score).toFixed(1)}/5` : ""} across {run.cases_total} test cases.
        </p>
      )}
    </aside>
  );
}

function HandledDialog({ action, pending, error, onApprove, onClose }: Props) {
  const day = action.kind === "ratio_risk" ? shortDay(action.facts.date) : "";
  const room = action.kind === "ratio_risk" ? action.facts.classroom_name : "";
  return (
    <Modal
      title="Mark as handled?"
      description={
        <p>
          Confirm you have coverage for {room} on {day}. Cubby will not raise it again for that day unless the
          schedule changes.
        </p>
      }
      onClose={onClose}
      footer={
        <>
          <button type="button" className="button button--quiet" onClick={onClose}>Cancel</button>
          <button type="button" className="button button--primary" data-autofocus disabled={pending} onClick={() => onApprove("")}>
            {pending ? "Saving…" : "Mark handled"}
          </button>
        </>
      }
    >
      {error && <p className="form-error" role="alert">{error}</p>}
    </Modal>
  );
}
