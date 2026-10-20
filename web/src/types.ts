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
}

export type ProposedAction =
  | (ActionBase & { kind: "past_due_invoice"; facts: PastDueFacts })
  | (ActionBase & { kind: "stale_waitlist"; facts: WaitlistFacts })
  | (ActionBase & { kind: "ratio_risk"; facts: RatioFacts });

export type ListName = "inbox" | "approved" | "dismissed";
