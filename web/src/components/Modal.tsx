import { useEffect, useId, useRef, type ReactNode } from "react";
import { createPortal } from "react-dom";

const FOCUSABLE = 'a[href], button:not([disabled]), textarea:not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';

interface Props {
  title: string;
  description?: ReactNode;
  onClose: () => void;
  footer: ReactNode;
  children?: ReactNode;
  variant?: "center" | "drawer";
}

// A custom dialog: focus moves in and is trapped, Escape and the backdrop close it, focus returns
// to the opener afterwards, and the page behind stops scrolling.
export function Modal({ title, description, onClose, footer, children, variant = "center" }: Props) {
  const panel = useRef<HTMLDivElement>(null);
  const close = useRef(onClose);
  close.current = onClose;
  const titleId = useId();
  const descId = useId();

  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    const node = panel.current;
    if (!node) return;
    (node.querySelector<HTMLElement>("[data-autofocus]") ?? node.querySelector<HTMLElement>(FOCUSABLE))?.focus();
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        close.current();
      } else if (e.key === "Tab") {
        const items = [...node.querySelectorAll<HTMLElement>(FOCUSABLE)];
        const first = items[0];
        const last = items[items.length - 1];
        if (!first || !last) return;
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault();
          last.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          first.focus();
        }
      }
    };
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = overflow;
      opener?.focus();
    };
  }, []);

  return createPortal(
    <div className={`overlay overlay--${variant}`} onMouseDown={(e) => e.target === e.currentTarget && close.current()}>
      <div
        ref={panel}
        className={`dialog dialog--${variant}`}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={description ? descId : undefined}
      >
        <header className="dialog__header">
          <h2 id={titleId}>{title}</h2>
          <button type="button" className="icon-button" onClick={() => close.current()} aria-label="Close">
            <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M5 5l10 10M15 5L5 15" /></svg>
          </button>
        </header>
        {description && <div id={descId} className="dialog__description">{description}</div>}
        {children && <div className="dialog__body">{children}</div>}
        <footer className="dialog__footer">{footer}</footer>
      </div>
    </div>,
    document.body,
  );
}
