class CreatePolicies < ActiveRecord::Migration[8.1]
  def change
    enable_extension "vector"

    # A center's handbook. Chunks are what drafts cite, so they keep a stable heading and position.
    create_table :policy_documents do |t|
      t.references :center, null: false, foreign_key: true
      t.string :title, null: false
      t.text :body, null: false
      t.string :body_digest, null: false
      t.timestamps
    end
    add_index :policy_documents, %i[center_id title], unique: true

    create_table :policy_chunks do |t|
      t.references :policy_document, null: false, foreign_key: true
      t.references :center, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :heading, null: false
      t.text :body, null: false
      # Titan Text Embeddings V2, 1024 dimensions, normalized.
      t.vector :embedding, limit: 1024
      t.timestamps
    end
    add_index :policy_chunks, %i[policy_document_id position], unique: true
    add_index :policy_chunks, :embedding, using: :hnsw, opclass: :vector_cosine_ops
  end
end
