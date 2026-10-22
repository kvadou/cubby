module Policies
  # (Re)builds a document's chunks and embeddings. Unchanged documents are skipped.
  module Indexer
    module_function

    def call(document, force: false)
      embed = Ai::Bedrock.embeddings?
      return :unchanged if !force && document.chunks.any? && (!embed || document.chunks.all? { |c| c.embedding.present? }) &&
                           document.chunks.first.updated_at >= document.updated_at

      sections = Chunker.call(document.body)
      # Without an embedding model the chunks are still stored, and Policies::Search reads them by full text.
      embeddings = sections.map { |s| embed ? Ai::Bedrock.embed("#{s.heading}\n#{s.body}") : nil }
      PolicyDocument.transaction do
        document.chunks.delete_all
        sections.each_with_index do |s, i|
          document.chunks.create!(center: document.center, position: i + 1, heading: s.heading, body: s.body,
                                  embedding: embeddings[i])
        end
      end
      :indexed
    end
  end
end
