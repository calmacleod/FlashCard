class DocumentTextExtractor
  def self.extract(document)
    raise ArgumentError, "Document has no attached file" unless document.file.attached?

    document.file.blob.open do |file|
      content = case document.file.content_type
      when "application/pdf"
        Pdftotext.text(file.path)
      when "text/plain"
        File.read(file.path, encoding: "UTF-8")
      else
        raise ArgumentError, "Unsupported document type: #{document.file.content_type}"
      end

      content.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end
  end
end
