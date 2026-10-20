module Api
  module V1
    module Parent
      class AttendancesController < BaseController
        MAX_DAYS = 60

        def index
          child = current_family.children.find(params[:child_id])
          days = (Integer(params[:days].to_s, exception: false) || 14).clamp(1, MAX_DAYS)
          today = current_family.center.today
          records = child.attendances.includes(:classroom).where(on: (today - (days - 1))..today).order(on: :desc)

          render json: records.map { |a|
            { on: a.on, classroom: a.classroom.name, checked_in_at: time(a.checked_in_at), checked_out_at: time(a.checked_out_at) }
          }
        end
      end
    end
  end
end
