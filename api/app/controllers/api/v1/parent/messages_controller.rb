module Api
  module V1
    module Parent
      class MessagesController < BaseController
        def index
          render json: current_family.messages.order(sent_at: :desc).limit(100).map { |m| message_json(m) }
        end

        # Idempotent: the first read time is kept.
        def read
          message = current_family.messages.find(params[:id])
          message.update!(read_at: Time.current) if message.read_at.nil?
          render json: message_json(message)
        end

        private

        def message_json(message)
          { id: message.id, subject: message.subject, body: message.body, sent_at: time(message.sent_at),
            read_at: time(message.read_at), from: current_family.center.name }
        end
      end
    end
  end
end
