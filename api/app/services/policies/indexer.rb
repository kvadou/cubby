module Policies
  # (Re)builds a document's chunks and embeddings. Unchanged documents are skipped.
  module Indexer
    module_function

    def call(document, force: false)
      return :unchanged if !force && document.chunks.any? && document.chunks.all? { |c| c.embedding.present? } &&
                           document.chunks.first.updated_at >= document.updated_at

      sections = Chunker.call(document.body)
      embeddings = sections.map { |s| Ai::Bedrock.embed("#{s.heading}\n#{s.body}") }
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
