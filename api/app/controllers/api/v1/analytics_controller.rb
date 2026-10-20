module Api
  module V1
    class AnalyticsController < BaseController
      def show
        days = Analytics::Report::WINDOWS.include?(params[:days].to_i) ? params[:days].to_i : 30
        render json: Analytics::Report.new(current_center, days: days).to_h
      end
    end
  end
end
