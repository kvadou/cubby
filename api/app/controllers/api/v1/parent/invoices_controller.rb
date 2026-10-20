module Api
  module V1
    module Parent
      class InvoicesController < BaseController
        def index
          today = current_family.center.today
          invoices = current_family.invoices.where.not(status: "void").order(due_on: :desc).limit(24)
          # What needs paying comes first.
          invoices = invoices.sort_by { |i| [ i.open? ? 0 : 1, i.open? ? i.due_on : -i.due_on.jd ] }

          render json: invoices.map { |i|
            { id: i.id, number: i.number, amount_cents: i.amount_cents, period_start: i.period_start,
              period_end: i.period_end, due_on: i.due_on, status: i.status, days_past_due: i.days_past_due(today),
              paid_at: time(i.paid_at) }
          }
        end
      end
    end
  end
end
