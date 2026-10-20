module Evals
  # Stands in for Ai::Bedrock.structured. Live mode calls Bedrock and saves each response; recorded mode
  # replays saved responses so CI grades drafts without AWS. The key covers the model and the full prompt,
  # so changing either one forces a re-record instead of silently grading a stale answer.
  class Recorder
    class MissingRecording < StandardError; end

    attr_reader :used

    def initialize(dir, live:)
      @dir = Pathname(dir)
      @live = live
      @used = []
    end

    def structured(model:, system:, prompt:, tool:, **options)
      key = Digest::SHA256.hexdigest([ model, system, prompt, tool[:name], JSON.generate(tool[:input_schema]) ].join("\u0000")).first(20)
      path = @dir.join("#{key}.json")
      @used << path
      if @live
        result = Ai::Bedrock.structured(model: model, system: system, prompt: prompt, tool: tool, **options)
        path.write(JSON.pretty_generate(result.to_h))
        result
      else
        raise MissingRecording, "no recording #{path.basename}; run `EVALS_LIVE=1 bin/rails evals:drafts` to record" unless path.exist?

        Ai::Bedrock::Result.new(**JSON.parse(path.read).symbolize_keys)
      end
    end

    # After a live run, drop recordings no case used any more.
    def prune!
      (@dir.glob("*.json") - @used).each(&:delete)
    end
  end
end
