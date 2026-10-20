import { useState } from "react";
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
  const [body, setBody] = useState(() => action.draft_body ?? starterMessage(action, directorName, centerName));
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
        <span>{action.draft_body ? "Draft" : "Starting text"} from Cubby. Edit anything before you approve.{lang ? ` The family prefers ${lang}.` : ""}</span>
        <span className={tooLong ? "danger" : undefined}>{body.length.toLocaleString()} / {MAX.toLocaleString()}</span>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </Modal>
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
