class PdfChunker
  Chunk = Data.define(:index, :title, :text)

  def self.chunk(text)
    lines = text.to_s.split("\n").map(&:strip)
    sections = []
    current_title = "Introduction"
    current_lines = []

    lines.each do |line|
      next if line.empty? && current_lines.empty?

      if heading?(line)
        sections << [current_title, current_lines.join("\n")] if current_lines.any?
        current_title = line
        current_lines = []
      else
        current_lines << line
      end
    end

    sections << [current_title, current_lines.join("\n")] if current_lines.any?

    if sections.empty?
      return [Chunk.new(index: 0, title: "Document", text: text)]
    end

    chunks = []
    sections.each do |title, section_text|
      split_large_section(section_text).each_with_index do |split_text, split_index|
        suffix = split_index.zero? ? "" : " (Part #{split_index + 1})"
        chunks << Chunk.new(index: chunks.length, title: "#{title}#{suffix}", text: split_text)
      end
    end

    chunks
  end

  def self.split_large_section(section_text, max_chars: 3500)
    return [section_text] if section_text.length <= max_chars

    paragraphs = section_text.split(/\n{2,}/)
    chunks = []
    current = +""

    paragraphs.each do |para|
      if current.length + para.length + 2 > max_chars && current.length > 0
        chunks << current.strip
        current = +""
      end
      current << "\n\n" unless current.empty?
      current << para
    end

    chunks << current.strip if current.length > 0
    chunks
  end

  def self.heading?(line)
    return true if line.match?(/\A(Chapter|Section)\b/i)
    return true if line.match?(/\A\d+(\.\d+)*\s+\S+/)
    return true if line == line.upcase && line.length >= 5

    false
  end
end
