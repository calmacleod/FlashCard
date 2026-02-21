module ApplicationHelper
  class ExternalLinkRenderer < Redcarpet::Render::HTML
    def link(link, title, content)
      title_attr = title.present? ? " title=\"#{CGI.escapeHTML(title)}\"" : ""
      "<a href=\"#{link}\"#{title_attr} target=\"_blank\" rel=\"noopener noreferrer\">#{content}</a>"
    end
  end

  def markdown(text)
    renderer = ExternalLinkRenderer.new(hard_wrap: true, safe_links_only: true)
    md = Redcarpet::Markdown.new(renderer, autolink: true, tables: true, fenced_code_blocks: true, strikethrough: true)
    md.render(text.to_s).html_safe
  end
end
