import type { AnalyticsReport, AskAnswer, EvalSummary, Me, ProposedAction, ListName } from "./types";

export interface ErrorBody {
  error?: string;
  message?: string;
  action?: ProposedAction;
}

export class ApiError extends Error {
  readonly status: number;
  readonly body: ErrorBody;

  constructor(status: number, body: ErrorBody) {
    super(body.message ?? body.error ?? `Request failed (${status})`);
    this.status = status;
    this.body = body;
  }
}

// Same-origin requests only: the browser adds Sec-Fetch-Site and the session cookie on its own.
export async function request<T>(path: string, init: { method?: string; body?: unknown } = {}): Promise<T> {
  const res = await fetch(`/api/v1${path}`, {
    method: init.method ?? "GET",
    credentials: "same-origin",
    headers: { Accept: "application/json", ...(init.body === undefined ? {} : { "Content-Type": "application/json" }) },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
  if (res.status === 204) return undefined as T;

  const body: unknown = await res.json().catch(() => ({}));
  if (!res.ok) throw new ApiError(res.status, (body ?? {}) as ErrorBody);
  return body as T;
}

export const api = {
  me: () => request<Me>("/me"),
  signIn: (email_address: string, password: string) =>
    request<Me>("/session", { method: "POST", body: { email_address, password } }),
  signOut: () => request<void>("/session", { method: "DELETE" }),

  analytics: (centerId: number, days: number) => request<AnalyticsReport>(`/centers/${centerId}/analytics?days=${days}`),
  latestEval: () => request<EvalSummary | null>("/evals/latest"),
  ask: (centerId: number, question: string) =>
    request<AskAnswer>(`/centers/${centerId}/ask`, { method: "POST", body: { question } }),

  actions: (centerId: number, list: ListName) =>
    request<ProposedAction[]>(`/centers/${centerId}/proposed_actions?status=${list}`),
  approve: (centerId: number, a: ProposedAction, final_body: string) =>
    request<ProposedAction>(`/centers/${centerId}/proposed_actions/${a.id}/approve`, {
      method: "POST",
      body: { lock_version: a.lock_version, final_body },
    }),
  dismiss: (centerId: number, a: ProposedAction, reason: string) =>
    request<ProposedAction>(`/centers/${centerId}/proposed_actions/${a.id}/dismiss`, {
      method: "POST",
      body: { lock_version: a.lock_version, reason },
    }),
  snooze: (centerId: number, a: ProposedAction, until: Date) =>
    request<ProposedAction>(`/centers/${centerId}/proposed_actions/${a.id}/snooze`, {
      method: "POST",
      body: { lock_version: a.lock_version, until: until.toISOString() },
    }),
};
