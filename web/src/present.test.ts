import { facts, money, snoozeOptions, starterMessage, title, timeAgo } from "./present";
import type { ProposedAction } from "./types";

const base = {
  id: 1, status: "proposed" as const, resolution: null, rationale: "r", occurs_on: null, detected_at: "", last_seen_at: "",
  snoozed_until: null, decided_at: null, decided_by_name: null, dismiss_reason: null, draft_body: null,
  final_body: null, lock_version: 0, family_facing: true, draft_status: "none" as const, draft_citations: [], draft_model: null,
};

const pastDue: ProposedAction = {
  ...base, kind: "past_due_invoice",
  facts: { guardian_first_name: "Roman", total_cents: 270000, invoice_numbers: ["LO-1162", "LO-1163"],
           oldest_due_on: "2026-09-01", max_days_past_due: 48 },
};

const ratio: ProposedAction = {
  ...base, kind: "ratio_risk", family_facing: false,
  facts: { date: "2026-10-20", classroom_name: "Saplings", expected_children: 11, teaching_staff: 1, staff_required: 2,
           ratio_applied: 7, mn_category: "toddler", group_size_limit: 14, over_group_size: false, youngest_age_months: 17 },
};

describe("present", () => {
  it("formats money from cents", () => {
    expect(money(270000)).toBe("$2,700.00");
  });

  it("titles each kind from its facts", () => {
    expect(title(pastDue)).toBe("$2,700.00 past due from Roman");
    expect(title(ratio)).toBe("Saplings needs 1 more teacher on Tue, Oct 20");
  });

  it("reads calendar days as local dates, not UTC", () => {
    expect(facts(pastDue)).toContainEqual({ label: "Oldest due", value: "Tue, Sep 1" });
  });

  it("drafts a starter message only for family-facing kinds", () => {
    const text = starterMessage(pastDue, "Renee Albright", "Little Oaks");
    expect(text).toContain("Hi Roman,");
    expect(text).toContain("$2,700.00 open on invoices LO-1162, LO-1163");
    expect(text).toContain("Tuesday, September 1");
    expect(text.endsWith("Renee Albright")).toBe(true);
    expect(starterMessage(ratio, "Renee Albright", "Little Oaks")).toBe("");
  });

  it("offers snooze times in the future at 8 AM", () => {
    const friday = new Date(2026, 9, 23, 15, 30);
    const [tomorrow, three, monday] = snoozeOptions(friday);
    expect(tomorrow?.until).toEqual(new Date(2026, 9, 24, 8));
    expect(three?.until).toEqual(new Date(2026, 9, 26, 8));
    expect(monday?.until).toEqual(new Date(2026, 9, 26, 8));
    const sunday = new Date(2026, 9, 25, 9);
    expect(snoozeOptions(sunday)[2]?.until).toEqual(new Date(2026, 9, 26, 8));
  });

  it("describes elapsed time", () => {
    const now = new Date("2026-10-19T12:00:00Z");
    expect(timeAgo("2026-10-19T11:58:00Z", now)).toBe("2 min ago");
    expect(timeAgo("2026-10-18T12:00:00Z", now)).toBe("yesterday");
  });
});

describe("ask steps", () => {
  it("labels tool calls in plain language", async () => {
    const { stepLabel } = await import("./components/AskPanel");
    expect(stepLabel({ tool: "find_family", input: { name: "Effertz" } })).toBe("Family records: Effertz");
    expect(stepLabel({ tool: "classroom_staffing", input: {} })).toBe("Staffing today");
    expect(stepLabel({ tool: "search_policies", input: { query: "late fee" } })).toBe("Handbook: “late fee”");
  });
});
