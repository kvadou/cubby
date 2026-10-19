module Api
  module V1
    class EnrollmentsController < BaseController
      def index
        scope = Enrollment.joins(child: :family).where(families: { center_id: current_center.id })
                          .includes(:classroom, child: :family)
        scope = scope.where(status: params[:status]) if Enrollment::STATUSES.include?(params[:status])
        scope = scope.order(Arel.sql("enrollments.waitlisted_at ASC NULLS LAST, children.last_name ASC"))
        today = current_center.today

        render json: scope.map { |e|
          {
            id: e.id,
            status: e.status,
            child: { id: e.child.id, first_name: e.child.first_name, last_name: e.child.last_name,
                     age_months: e.child.age_in_months(today) },
            family: { id: e.child.family.id, name: e.child.family.name },
            classroom: e.classroom && { id: e.classroom.id, name: e.classroom.name },
            schedule_days: e.schedule_days,
            waitlisted_at: e.waitlisted_at,
            days_on_waitlist: e.waitlisted? ? e.days_on_waitlist : nil,
            last_contacted_at: e.last_contacted_at,
            requested_start_on: e.requested_start_on
          }
        }
      end
    end
  end
end
