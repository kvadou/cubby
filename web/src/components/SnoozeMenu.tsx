import { useEffect, useId, useRef, useState } from "react";
import { snoozeOptions } from "../present";

interface Props {
  onPick: (until: Date, label: string) => void;
  disabled?: boolean;
}

export function SnoozeMenu({ onPick, disabled }: Props) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const button = useRef<HTMLButtonElement>(null);
  const menuId = useId();
  const options = snoozeOptions();

  useEffect(() => {
    if (!open) return;
    root.current?.querySelector<HTMLElement>('[role="menuitem"]')?.focus();
    const onDown = (e: MouseEvent) => {
      if (!root.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, [open]);

  const onMenuKey = (e: React.KeyboardEvent) => {
    const items = [...(root.current?.querySelectorAll<HTMLElement>('[role="menuitem"]') ?? [])];
    const i = items.indexOf(document.activeElement as HTMLElement);
    if (e.key === "Escape" || e.key === "Tab") {
      setOpen(false);
      if (e.key === "Escape") button.current?.focus();
    } else if (e.key === "ArrowDown") {
      e.preventDefault();
      items[(i + 1) % items.length]?.focus();
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      items[(i - 1 + items.length) % items.length]?.focus();
    }
  };

  return (
    <div className="menu" ref={root}>
      <button
        ref={button}
        type="button"
        className="button button--quiet"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={open ? menuId : undefined}
        disabled={disabled}
        onClick={() => setOpen((o) => !o)}
      >
        Snooze
        <svg className="chevron" viewBox="0 0 20 20" aria-hidden="true"><path d="M6 8l4 4 4-4" /></svg>
      </button>
      {open && (
        <div className="menu__list" role="menu" id={menuId} onKeyDown={onMenuKey}>
          {options.map((o) => (
            <button
              key={o.label}
              type="button"
              role="menuitem"
              className="menu__item"
              onClick={() => {
                setOpen(false);
                onPick(o.until, o.label);
              }}
            >
              <span>{o.label}</span>
              <span className="menu__hint">
                {o.until.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" })}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
