module Policies
  # Nearest handbook sections to a query, within one center, by cosine distance.
  module Search
    module_function

    def call(center, query, limit: 3)
      return [] unless PolicyChunk.where(center: center).where.not(embedding: nil).exists?

      PolicyChunk.where(center: center).includes(:policy_document)
                 .nearest_neighbors(:embedding, Ai::Bedrock.embed(query), distance: "cosine").first(limit)
    end
  end
end
