require "pdf/reader"

class PdfTextExtractor
  ExtractionError = Class.new(StandardError)

  def self.extract(path, max_chars: 12_000)
    reader = PDF::Reader.new(path)
    text = reader.pages.map(&:text).join("\n").strip

    return text if text.length <= max_chars

    text[0, max_chars]
  rescue PDF::Reader::MalformedPDFError, ArgumentError => error
    raise ExtractionError, "Unable to read the PDF: #{error.message}"
  end
end
