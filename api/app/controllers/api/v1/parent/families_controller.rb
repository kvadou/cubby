module Api
  module V1
    module Parent
      class FamiliesController < BaseController
        def show
          family = current_family
          today = family.center.today
          children = family.children.includes(enrollments: :classroom).order(:first_name)
          attendance = Attendance.where(child: children, on: today).index_by(&:child_id)

          render json: {
            family: { id: family.id, name: family.name, guardian_name: family.primary_guardian_name },
            center: family.center.slice(:name, :city, :timezone).merge(director_name: family.center.director_name),
            today: today,
            unread_messages: family.messages.unread.count,
            children: children.map { |child|
              enrollment = child.enrollments.find { |e| %w[waitlisted enrolled].include?(e.status) } # preloaded
              day = attendance[child.id]
              {
                id: child.id,
                first_name: child.first_name,
                classroom: enrollment&.classroom&.name,
                status: enrollment&.status,
                today: day && { checked_in_at: time(day.checked_in_at), checked_out_at: time(day.checked_out_at) }
              }
            }
          }
        end
      end
    end
  end
end
