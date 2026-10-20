module Api
  module V1
    class AsksController < BaseController
      MAX_QUESTION = 500

      rate_limit to: 20, within: 10.minutes, only: :create, by: -> { Current.user.id }, scope: "ask",
                 with: -> { render json: { error: "rate_limited", message: "That's a lot of questions. Try again in a few minutes." }, status: :too_many_requests }
      # Daily ceilings on Bedrock spend: per user, and for everyone together (the demo logins are shared).
      rate_limit to: 100, within: 1.day, only: :create, by: -> { Current.user.id }, scope: "ask", name: "user-daily",
                 with: -> { render json: { error: "rate_limited", message: "That's today's limit for your account. Try again tomorrow." }, status: :too_many_requests }
      rate_limit to: ENV.fetch("CUBBY_ASK_DAILY_LIMIT", 300).to_i, within: 1.day, only: :create, by: -> { "all" },
                 scope: "ask", name: "daily",
                 with: -> { render json: { error: "rate_limited", message: "Ask Cubby has hit today's limit. Try again tomorrow." }, status: :too_many_requests }

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
