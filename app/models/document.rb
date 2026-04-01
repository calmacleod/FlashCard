class Document < ApplicationRecord
  has_one_attached :file
  has_many :flashcards, dependent: :destroy

  PROCESSING_STATUSES = %w[processing completed failed].freeze

  ALLOWED_CONTENT_TYPES = %w[application/pdf text/plain].freeze

  validates :name, presence: true
  validate :valid_extraction_schema_json

  def progress
    return {} if processing_progress.blank?
    JSON.parse(processing_progress)
  rescue JSON::ParserError
    {}
  end

  def extraction_schema_hash
    return nil if extraction_schema.blank?
    JSON.parse(extraction_schema)
  rescue JSON::ParserError
    nil
  end
  validate :file_attached
  validate :acceptable_file_type, if: -> { file.attached? }

  private

  def valid_extraction_schema_json
    return if extraction_schema.blank?
    JSON.parse(extraction_schema)
  rescue JSON::ParserError
    errors.add(:extraction_schema, "is not valid JSON")
  end

  def file_attached
    errors.add(:file, "must be attached") unless file.attached?
  end

  def acceptable_file_type
    unless ALLOWED_CONTENT_TYPES.include?(file.content_type)
      errors.add(:file, "must be a PDF or plain text file")
    end
  end
end
