module Api
  module V1
    class ClassroomsController < BaseController
      def index
        date = params[:on].present? ? Date.parse(params[:on].to_s) : current_center.today
        rooms = current_center.classrooms.order(:age_min_months).map do |room|
          expected = room.expected_children_on(date)
          {
            id: room.id,
            name: room.name,
            age_range_months: [ room.age_min_months, room.age_max_months ],
            capacity: room.capacity,
            ratio: room.ratio,
            enrolled: room.enrolled_count,
            open_seats: room.open_seats,
            on: date,
            expected_children: expected,
            scheduled_staff: room.staff_shifts.on_date(date).count,
            staff_required: room.staff_required_for(expected)
          }
        end
        render json: rooms
      rescue Date::Error
        render json: { error: "invalid_date" }, status: :unprocessable_content
      end
    end
  end
end
