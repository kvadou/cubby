export type Kind = "stale_waitlist" | "past_due_invoice" | "ratio_risk";
export type Status = "proposed" | "approved" | "dismissed" | "resolved";

export interface Center {
  id: number;
  name: string;
  city: string;
  timezone: string;
}

export interface Me {
  user: { id: number; name: string; email_address: string };
  centers: Center[];
}

export interface PastDueFacts {
  guardian_first_name: string;
  total_cents: number;
  invoice_numbers: string[];
  oldest_due_on: string;
  max_days_past_due: number;
  preferred_language?: string;
}

export interface WaitlistFacts {
  guardian_first_name: string;
  child_first_name: string;
  age_months: number;
  classroom_name: string;
  open_seats: number;
  days_on_waitlist: number;
  days_since_contact: number | null;
  requested_start_on: string;
  preferred_language?: string;
}

export interface RatioFacts {
  date: string;
  classroom_name: string;
  expected_children: number;
  teaching_staff: number;
  staff_required: number;
  ratio_applied: number;
  mn_category: string;
  group_size_limit: number;
  over_group_size: boolean;
  youngest_age_months: number;
}

interface ActionBase {
  id: number;
  status: Status;
  resolution: string | null;
  rationale: string;
  occurs_on: string | null;
  detected_at: string;
  last_seen_at: string;
  snoozed_until: string | null;
  decided_at: string | null;
  decided_by_name: string | null;
  dismiss_reason: string | null;
  draft_body: string | null;
  final_body: string | null;
  lock_version: number;
  family_facing: boolean;
  draft_status: DraftStatus;
  draft_citations: { chunk_id: number; heading: string }[];
  draft_model: string | null;
}

export type DraftStatus = "none" | "pending" | "ready" | "failed";

export interface EvalSummary {
  mode: "recorded" | "live";
  model: string;
  judge_model: string | null;
  cases_total: number;
  checks_passed: number;
  checks_total: number;
  judge_score: string | null;
  created_at: string;
}

export interface AskStep {
  tool: string;
  input: Record<string, unknown>;
}

export interface AskAnswer {
  text: string;
  steps: AskStep[];
  model: string;
  cost_micros: number | null;
}

export type ProposedAction =
  | (ActionBase & { kind: "past_due_invoice"; facts: PastDueFacts })
  | (ActionBase & { kind: "stale_waitlist"; facts: WaitlistFacts })
  | (ActionBase & { kind: "ratio_risk"; facts: RatioFacts });

export type ListName = "inbox" | "approved" | "dismissed";

export interface KindStats {
  kind: Kind;
  proposed: number;
  approved: number;
  dismissed: number;
  resolved: number;
  median_hours_to_decision: number | null;
}

export interface AnalyticsReport {
  days: number;
  since: string;
  totals: { proposed: number; approved: number; dismissed: number; resolved: number; snoozed: number; approval_rate: number | null };
  by_kind: KindStats[];
  median_hours_to_decision: number | null;
  messages: { approved: number; draft_as_is: number; draft_edited: number; starter_or_own: number };
  ai: { drafts: number; drafts_ready: number; cost_micros: number; cost_per_approved_message_micros: number | null };
  daily: { date: string; approved: number; dismissed: number }[];
  pipeline: { waiting_to_publish: number; last_received_at: string | null };
}
