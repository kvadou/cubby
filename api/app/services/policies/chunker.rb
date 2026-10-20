module Policies
  # Splits a handbook on "## " headings. Handbook sections are short and self-contained, so one
  # section is one chunk and a citation points at something a director recognizes.
  module Chunker
    Section = Data.define(:heading, :body)

    module_function

    def call(markdown)
      markdown.split(/^## /).drop(1).filter_map do |part|
        heading, *rest = part.lines
        body = rest.join.strip
        Section.new(heading: heading.strip, body: body) if body.present?
      end
    end
  end
end
