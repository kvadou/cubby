import { useState, type FormEvent } from "react";
import { useMutation } from "@tanstack/react-query";
import { api, ApiError } from "../api";
import type { AskAnswer, AskStep, Center } from "../types";
import { Modal } from "./Modal";

const SUGGESTIONS = [
  "Which classrooms have open seats?",
  "Who is waiting for a toddler spot?",
  "What is our late fee policy?",
  "Are we covered on staff tomorrow?",
];

interface Exchange {
  question: string;
  answer: AskAnswer;
}

export function stepLabel(step: AskStep): string {
  const value = (key: string) => (typeof step.input[key] === "string" ? (step.input[key] as string) : "");
  switch (step.tool) {
    case "find_family": return `Family records: ${value("name")}`;
    case "classroom_staffing": return value("date") ? `Staffing on ${value("date")}` : "Staffing today";
    case "waitlist": return value("classroom_name") ? `Waitlist for ${value("classroom_name")}` : "Waitlist";
    case "search_policies": return `Handbook: “${value("query")}”`;
    case "open_actions": return "Your queue";
    default: return step.tool;
  }
}

export function AskPanel({ center, onClose }: { center: Center; onClose: () => void }) {
  const [question, setQuestion] = useState("");
  const [history, setHistory] = useState<Exchange[]>([]);
  const ask = useMutation({
    mutationFn: (q: string) => api.ask(center.id, q),
    onSuccess: (answer, q) => {
      setHistory((h) => [{ question: q, answer }, ...h]);
      setQuestion("");
    },
  });

  const submit = (e?: FormEvent, text = question) => {
    e?.preventDefault();
    const q = text.trim();
    if (q && !ask.isPending) ask.mutate(q);
  };

  const error = ask.error instanceof ApiError ? ask.error.message : ask.error ? "Couldn't reach Cubby. Try again." : null;

  return (
    <Modal
      variant="drawer"
      title="Ask Cubby"
      description={<p>Questions about {center.name}: families, balances, staffing, the waitlist, or the handbook. Cubby can look things up but can't change anything.</p>}
      onClose={onClose}
      footer={
        <>
          <button type="button" className="button button--quiet" onClick={onClose}>Close</button>
          <button type="submit" form="ask-form" className="button button--primary" disabled={ask.isPending || !question.trim()}>
            {ask.isPending ? "Looking it up…" : "Ask"}
          </button>
        </>
      }
    >
      <form id="ask-form" onSubmit={submit}>
        <label className="field">
          <span className="field__label">Your question</span>
          <textarea
            data-autofocus
            className="field__input"
            rows={3}
            maxLength={500}
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) submit(e);
            }}
          />
        </label>
      </form>

      {history.length === 0 && !ask.isPending && (
        <div className="suggestions" role="group" aria-label="Suggested questions">
          {SUGGESTIONS.map((s) => (
            <button key={s} type="button" className="chip" onClick={() => { setQuestion(s); submit(undefined, s); }}>
              {s}
            </button>
          ))}
        </div>
      )}

      {error && <p className="form-error" role="alert">{error}</p>}

      <div className="answers" aria-live="polite">
        {ask.isPending && <div className="answer answer--pending">Looking through {center.name}'s records…</div>}
        {history.map((x, i) => (
          <article key={history.length - i} className="answer">
            <p className="answer__question">{x.question}</p>
            <p className="answer__text">{x.answer.text}</p>
            {x.answer.steps.length > 0 && (
              <p className="answer__steps">
                <span className="muted">Looked at:</span>{" "}
                {x.answer.steps.map((s, j) => <span key={j} className="step">{stepLabel(s)}</span>)}
              </p>
            )}
          </article>
        ))}
      </div>
    </Modal>
  );
}
