module Api
  module V1
    class MeController < BaseController
      def show
        render json: me_json
      end
    end
  end
end
