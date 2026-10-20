import { useId, useState } from "react";
import { title } from "../present";
import type { ProposedAction } from "../types";
import { Modal } from "./Modal";

const REASONS = ["Already handled", "Not accurate", "Family asked us to wait", "Something else"] as const;

interface Props {
  action: ProposedAction;
  pending: boolean;
  error: string | null;
  onDismiss: (reason: string) => void;
  onClose: () => void;
}

export function DismissDialog({ action, pending, error, onDismiss, onClose }: Props) {
  const [choice, setChoice] = useState<(typeof REASONS)[number]>("Already handled");
  const [note, setNote] = useState("");
  const name = useId();
  const needsNote = choice === "Something else" && note.trim() === "";
  const reason = note.trim() ? `${choice}: ${note.trim()}` : choice;

  return (
    <Modal
      title="Dismiss this item?"
      description={<p>{title(action)}. Cubby keeps a record of why, and won't raise the same item again for a while.</p>}
      onClose={onClose}
      footer={
        <>
          <button type="button" className="button button--quiet" onClick={onClose}>Cancel</button>
          <button
            type="button"
            className="button button--danger"
            disabled={pending || needsNote}
            onClick={() => onDismiss(reason)}
          >
            {pending ? "Dismissing…" : "Dismiss"}
          </button>
        </>
      }
    >
      <fieldset className="choices">
        <legend className="field__label">Reason</legend>
        {REASONS.map((r, i) => (
          <label key={r} className="choice">
            <input
              type="radio"
              name={name}
              value={r}
              checked={choice === r}
              onChange={() => setChoice(r)}
              data-autofocus={i === 0 ? true : undefined}
            />
            <span>{r}</span>
          </label>
        ))}
      </fieldset>
      <label className="field">
        <span className="field__label">Note {choice === "Something else" ? "" : <span className="muted">(optional)</span>}</span>
        <textarea className="field__input" rows={3} maxLength={400} value={note} onChange={(e) => setNote(e.target.value)} />
      </label>
      {error && <p className="form-error" role="alert">{error}</p>}
    </Modal>
  );
}
