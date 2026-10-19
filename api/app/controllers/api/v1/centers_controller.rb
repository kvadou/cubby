module Api
  module V1
    class CentersController < BaseController
      def index
        render json: Center.order(:name).map { |c| { id: c.id, name: c.name, city: c.city } }
      end

      def show
        center = Center.find(params[:id])
        render json: {
          id: center.id,
          name: center.name,
          city: center.city,
          timezone: center.timezone,
          director_name: center.director_name,
          today: center.today,
          counts: {
            enrolled: Enrollment.enrolled.joins(:classroom).where(classrooms: { center_id: center.id }).count,
            waitlisted: Enrollment.waitlisted.joins(child: :family).where(families: { center_id: center.id }).count,
            families: center.families.count,
            staff: center.staff_members.count,
            past_due_invoices: Invoice.past_due(center.today).joins(:family).where(families: { center_id: center.id }).count
          }
        }
      end
    end
  end
end
