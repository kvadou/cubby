module Api
  module V1
    module Parent
      # Family endpoints for parents. Every query starts from the signed-in user's own family, the way
      # director endpoints start from their centers, so another family's data is a 404.
      class BaseController < Api::V1::BaseController
        rate_limit to: 300, within: 5.minutes, by: -> { Current.user.id }, scope: "family",
                   with: -> { render json: { error: "rate_limited", message: "Slow down a little and try again." }, status: :too_many_requests }

        private

        def current_family
          @current_family ||= Current.user.families.includes(:center).order(:id).first!
        end

        def time(value)
          value&.in_time_zone(current_family.center.timezone)&.iso8601
        end
      end
    end
  end
end
