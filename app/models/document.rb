class Document < ApplicationRecord
  has_one_attached :file

  ALLOWED_CONTENT_TYPES = %w[application/pdf text/plain].freeze

  validates :name, presence: true
  validate :file_attached
  validate :acceptable_file_type, if: -> { file.attached? }

  private

  def file_attached
    errors.add(:file, "must be attached") unless file.attached?
  end

  def acceptable_file_type
    unless ALLOWED_CONTENT_TYPES.include?(file.content_type)
      errors.add(:file, "must be a PDF or plain text file")
    end
  end
end
