require "rails_helper"

RSpec.describe "Policies" do
  let(:center) { create(:center) }

  it "chunks the seeded handbook into its sections" do
    sections = Policies::Chunker.call(Rails.root.join("db/seeds/policies/little_oaks_family_handbook.md").read)
    expect(sections.map(&:heading)).to include("Late payments and late fees", "Enrollment offers")
    expect(sections).to all(have_attributes(body: be_present))
  end

  it "indexes a document and skips it while unchanged" do
    allow(Ai::Bedrock).to receive(:embed).and_return(axis_vector(0))
    doc = center.policy_documents.create!(title: "Handbook", body: "## A\nOne.\n\n## B\nTwo.")

    expect(Policies::Indexer.call(doc)).to eq(:indexed)
    expect(doc.chunks.pluck(:heading, :position)).to eq([ [ "A", 1 ], [ "B", 2 ] ])
    expect(Policies::Indexer.call(doc.reload)).to eq(:unchanged)
    expect(Ai::Bedrock).to have_received(:embed).twice
  end

  it "searches by cosine distance within one center only" do
    other = create(:center)
    mine = center.policy_documents.create!(title: "H", body: "x")
    theirs = other.policy_documents.create!(title: "H", body: "x")
    mine.chunks.create!(center: center, position: 1, heading: "Fees", body: "fees", embedding: axis_vector(0))
    mine.chunks.create!(center: center, position: 2, heading: "Naps", body: "naps", embedding: axis_vector(5))
    theirs.chunks.create!(center: other, position: 1, heading: "Their fees", body: "fees", embedding: axis_vector(0))
    allow(Ai::Bedrock).to receive(:embed).and_return(axis_vector(0))

    expect(Policies::Search.call(center, "late fee", limit: 2).map(&:heading)).to eq(%w[Fees Naps])
  end

  it "returns nothing, without calling Bedrock, when a center has no policies" do
    allow(Ai::Bedrock).to receive(:embed)
    expect(Policies::Search.call(center, "fees")).to eq([])
    expect(Ai::Bedrock).not_to have_received(:embed)
  end

  it "ranks by full text, within one center, when chunks have no embeddings" do
    other = create(:center)
    mine = center.policy_documents.create!(title: "H", body: "x")
    theirs = other.policy_documents.create!(title: "H", body: "x")
    mine.chunks.create!(center: center, position: 1, heading: "Naps", body: "Quiet time after lunch.")
    mine.chunks.create!(center: center, position: 2, heading: "Late payments and late fees", body: "A $25 late fee applies after 10 days.")
    theirs.chunks.create!(center: other, position: 1, heading: "Late fees", body: "Their late fee policy.")
    allow(Ai::Bedrock).to receive(:embed)

    expect(Policies::Search.call(center, "What is the late fee for tuition?").map(&:heading)).to eq([ "Late payments and late fees" ])
    expect(Policies::Search.call(center, "the and of")).to eq([])
    expect(Ai::Bedrock).not_to have_received(:embed)
  end

  it "stores chunks without embeddings when the provider has no embedding model" do
    allow(Ai::Bedrock).to receive(:embeddings?).and_return(false)
    allow(Ai::Bedrock).to receive(:embed)
    doc = center.policy_documents.create!(title: "Handbook", body: "## A\nOne.\n\n## B\nTwo.")

    expect(Policies::Indexer.call(doc)).to eq(:indexed)
    expect(doc.chunks.pluck(:heading, :embedding)).to eq([ [ "A", nil ], [ "B", nil ] ])
    expect(Policies::Indexer.call(doc.reload)).to eq(:unchanged)
    expect(Ai::Bedrock).not_to have_received(:embed)
  end
end
