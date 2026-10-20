class IndexPolicyDocumentJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 5

  def perform(document_id)
    document = PolicyDocument.find_by(id: document_id)
    Policies::Indexer.call(document) if document
  end
end
