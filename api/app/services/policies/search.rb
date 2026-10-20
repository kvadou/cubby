module Policies
  # Nearest handbook sections to a query, within one center, by cosine distance.
  module Search
    module_function

    def call(center, query, limit: 3)
      return [] unless PolicyChunk.where(center: center).where.not(embedding: nil).exists?

      vector = Ai::Bedrock.embed(query)
      # HNSW filters by center after the scan; iterative scan (pgvector 0.8+) keeps searching until
      # enough of this center's rows are found, so a small center still gets its full `limit`.
      PolicyChunk.transaction do
        PolicyChunk.connection.execute("SET LOCAL hnsw.iterative_scan = relaxed_order")
        PolicyChunk.where(center: center).includes(:policy_document)
                   .nearest_neighbors(:embedding, vector, distance: "cosine").first(limit)
      end
    end
  end
end
