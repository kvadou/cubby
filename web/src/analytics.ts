// Formatting for the analytics page. Plain functions so they can be unit tested.

export function duration(hours: number | null): string {
  if (hours === null) return "No decisions yet";
  if (hours < 1) return `${Math.max(1, Math.round(hours * 60))} min`;
  if (hours < 48) return `${Math.round(hours * 10) / 10} hr`;
  return `${Math.round((hours / 24) * 10) / 10} days`;
}

export function percent(part: number, whole: number): string {
  return whole > 0 ? `${Math.round((part / whole) * 100)}%` : "No data";
}

// Micro-dollars to a price that still shows sub-cent AI costs.
export function microDollars(micros: number | null): string {
  if (micros === null) return "No AI drafts yet";
  const dollars = micros / 1_000_000;
  return dollars < 0.01 ? `$${dollars.toFixed(4)}` : `$${dollars.toFixed(2)}`;
}

// Tick labels for a daily chart: about six evenly spaced, always including the last day.
export function tickIndexes(count: number, ticks = 6): number[] {
  if (count <= ticks) return Array.from({ length: count }, (_, i) => i);
  const step = (count - 1) / (ticks - 1);
  return Array.from({ length: ticks }, (_, i) => Math.round(i * step));
}
