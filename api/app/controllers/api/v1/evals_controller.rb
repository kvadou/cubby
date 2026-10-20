module Api
  module V1
    # Latest draft eval, shown beside drafts so a director can see how drafts are graded.
    class EvalsController < BaseController
      def latest
        run = EvalRun.where(suite: "drafts").order(created_at: :desc).first
        return render(json: nil) unless run

        render json: run.slice(:suite, :mode, :model, :judge_model, :cases_total, :checks_passed, :checks_total,
                               :judge_score, :created_at)
      end
    end
  end
end
