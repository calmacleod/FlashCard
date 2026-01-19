class FlashCardChunk < ApplicationRecord
  belongs_to :flash_card_request

  validates :index, presence: true
  validates :content_text, presence: true

  def path
    JSON.parse(path_json.to_s)
  rescue JSON::ParserError
    []
  end
end
