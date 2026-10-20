# The Little Oaks family handbook, chunked and embedded by IndexPolicyDocumentJob (needs Bedrock access).
center = Center.find_by!(name: "Little Oaks Early Learning")
doc = center.policy_documents.find_or_initialize_by(title: "Family handbook")
doc.body = Rails.root.join("db/seeds/policies/little_oaks_family_handbook.md").read
doc.save! if doc.changed?
IndexPolicyDocumentJob.perform_async(doc.id)
puts "Queued handbook indexing for #{center.name}."
