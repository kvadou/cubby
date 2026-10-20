module Api
  module V1
    class AsksController < BaseController
      MAX_QUESTION = 500

      rate_limit to: 20, within: 10.minutes, only: :create, by: -> { Current.user.id }, scope: "ask",
                 with: -> { render json: { error: "rate_limited", message: "That's a lot of questions. Try again in a few minutes." }, status: :too_many_requests }

      def create
        question = params[:question].to_s.strip
        return render_invalid("Ask a question.") if question.empty?
        return render_invalid("Keep questions under #{MAX_QUESTION} characters.") if question.length > MAX_QUESTION

        answer = Agent::AskCubby.new(center: current_center).call(question)
        render json: answer.to_h
      rescue Ai::Bedrock::Error => e
        Rails.logger.warn("ask_cubby failed center=#{current_center.id}: #{e.message}")
        render json: { error: "ai_unavailable", message: "Cubby can't answer right now. Try again in a minute." },
               status: :service_unavailable
      end
    end
  end
end
