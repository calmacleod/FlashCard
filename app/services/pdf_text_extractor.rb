require "pdf/reader"

class PdfTextExtractor
  ExtractionError = Class.new(StandardError)

  def self.extract(path, max_chars: 12_000)
    reader = PDF::Reader.new(path)
    # Include explicit page markers so downstream chunking can strongly prefer
    # boundaries that do not span pages.
    text =
      reader.pages.map.with_index(1) do |page, page_number|
        <<~PAGE
          <<<PAGE #{page_number}>>>
          #{page.text.to_s.strip}
        PAGE
      end.join("\n").strip

    return text if text.length <= max_chars

    text[0, max_chars]
  rescue PDF::Reader::MalformedPDFError, ArgumentError => error
    raise ExtractionError, "Unable to read the PDF: #{error.message}"
  end
end
