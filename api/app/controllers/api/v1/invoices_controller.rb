module Api
  module V1
    class InvoicesController < BaseController
      def index
        today = current_center.today
        scope = Invoice.joins(:family).where(families: { center_id: current_center.id }).includes(:family)
        scope = case params[:status]
        when "past_due" then scope.past_due(today)
        when *Invoice::STATUSES then scope.where(status: params[:status])
        else scope
        end

        render json: scope.order(due_on: :desc, number: :asc).map { |i|
          {
            id: i.id,
            number: i.number,
            family: { id: i.family.id, name: i.family.name },
            amount_cents: i.amount_cents,
            period_start: i.period_start,
            period_end: i.period_end,
            due_on: i.due_on,
            status: i.status,
            days_past_due: i.days_past_due(today),
            paid_at: i.paid_at
          }
        }
      end
    end
  end
end
