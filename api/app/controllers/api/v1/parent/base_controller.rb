module Api
  module V1
    module Parent
      # Family endpoints for parents. Every query starts from the signed-in user's own family, the way
      # director endpoints start from their centers, so another family's data is a 404.
      class BaseController < Api::V1::BaseController
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
