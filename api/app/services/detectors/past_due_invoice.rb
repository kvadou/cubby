module Detectors
  # One action per family covering every open invoice due before today in the center's time zone,
  # i.e. from the morning after the due date (prior-art record D10, matching Brightwheel and Famly).
  class PastDueInvoice
    KIND = "past_due_invoice"
    VERSION = 1

    def initialize(center, as_of:)
      @center = center
      @as_of = as_of
    end

    def call
      invoices = Invoice.past_due(@as_of).joins(:family).where(families: { center_id: @center.id })
                        .includes(:family).order(:due_on, :number)

      invoices.group_by(&:family).map do |family, family_invoices|
        total = family_invoices.sum(&:amount_cents)
        oldest = family_invoices.first
        Candidate.new(
          kind: KIND, subject: family, dedupe_key: "#{KIND}:family:#{family.id}",
          rationale: "#{family.name} owes #{format('$%.2f', total / 100.0)} across #{family_invoices.size} " \
                     "invoice#{'s' if family_invoices.size > 1}; the oldest is #{oldest.days_past_due(@as_of)} days past due.",
          facts: {
            guardian_first_name: family.guardian_first_name,
            preferred_language: family.preferred_language,
            invoice_numbers: family_invoices.map(&:number),
            total_cents: total,
            oldest_due_on: oldest.due_on.iso8601,
            max_days_past_due: oldest.days_past_due(@as_of)
          },
          occurs_on: nil, detector_version: VERSION
        )
      end
    end
  end
end
