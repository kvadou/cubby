module Policies
  # Nearest handbook sections to a query, within one center, by cosine distance. Without embeddings
  # (no embedding model, or chunks indexed before one was available) it ranks by Postgres full text.
  module Search
    module_function

    def call(center, query, limit: 3)
      chunks = PolicyChunk.where(center: center)
      return full_text(chunks, query, limit) unless Ai::Bedrock.embeddings? && chunks.where.not(embedding: nil).exists?

      vector = Ai::Bedrock.embed(query)
      # HNSW filters by center after the scan; iterative scan (pgvector 0.8+) keeps searching until
      # enough of this center's rows are found, so a small center still gets its full `limit`.
      PolicyChunk.transaction do
        PolicyChunk.connection.execute("SET LOCAL hnsw.iterative_scan = relaxed_order")
        PolicyChunk.where(center: center).includes(:policy_document)
                   .nearest_neighbors(:embedding, vector, distance: "cosine").first(limit)
      end
    end

    # Any query word can match (OR), ranked by how well the section matches; stop words drop out.
    def full_text(chunks, query, limit)
      words = query.to_s.downcase.scan(/[a-z0-9]+/).uniq.first(20)
      return [] if words.empty?

      document = "to_tsvector('english', policy_chunks.heading || ' ' || policy_chunks.body)"
      tsquery = PolicyChunk.sanitize_sql_array([ "to_tsquery('english', ?)", words.join(" | ") ])
      chunks.includes(:policy_document).where("#{document} @@ #{tsquery}")
            .order(Arel.sql("ts_rank(#{document}, #{tsquery}) DESC, policy_chunks.position")).limit(limit).to_a
    end
  end
end
