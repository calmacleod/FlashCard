class RulebookChunk < ApplicationRecord
  STATUSES = %w[pending completed failed].freeze

  validates :pdf_path,    presence: true
  validates :chunk_index, presence: true,
                          uniqueness: { scope: :pdf_path }
  validates :chunk_text,  presence: true
  validates :status,      inclusion: { in: STATUSES }

  scope :for_pdf,   ->(path) { where(pdf_path: path).order(:chunk_index) }
  scope :pending,   -> { where(status: "pending") }
  scope :completed, -> { where(status: "completed") }

  def units
    return [] if units_json.blank?
    JSON.parse(units_json)
  rescue JSON::ParserError
    []
  end

  def completed?
    status == "completed"
  end
end
