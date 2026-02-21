class RuleSearcher
  def self.search(query, source_csv: nil, rule_number: nil, section: nil, article: nil, limit: 10)
    vector = OllamaClient.new(base_url: ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434"))
                          .embed(text: query, model: ENV.fetch("OLLAMA_EMBEDDING_MODEL", "bge-m3"))
                          .vector

    conn = ActiveRecord::Base.connection
    source_filter  = source_csv.present?  ? "AND source_csv = #{conn.quote(source_csv)}"              : ""
    rule_filter    = rule_number.present? ? "AND rule_number LIKE #{conn.quote("%#{rule_number}%")}"  : ""
    section_filter = section.present?     ? "AND section LIKE #{conn.quote("%#{section}%")}"          : ""
    article_filter = article.present?     ? "AND article LIKE #{conn.quote("%#{article}%")}"          : ""

    sql = <<~SQL
      SELECT *, vec_distance_cosine(embedding, ?) AS distance
      FROM rulebook_entries
      WHERE embedding IS NOT NULL #{source_filter} #{rule_filter} #{section_filter} #{article_filter}
      ORDER BY distance
      LIMIT #{limit.to_i}
    SQL

    blob = vector.pack("f*")
    bind = ActiveRecord::Relation::QueryAttribute.new(
      "embedding",
      blob,
      ActiveRecord::Type::Binary.new
    )

    ActiveRecord::Base.connection.exec_query(sql, "RuleSearch", [ bind ]).map do |row|
      {
        text:        row["text"],
        article:     row["article"],
        section:     row["section"],
        rule_number: row["rule_number"],
        source_csv:  row["source_csv"],
        distance:    row["distance"]
      }
    end
  end
end
