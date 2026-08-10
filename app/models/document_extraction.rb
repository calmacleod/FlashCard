class DocumentExtraction < ApplicationRecord
  STATUSES = %w[queued processing completed failed].freeze

  belongs_to :document

  validates :status, inclusion: { in: STATUSES }
  validates :schema_snapshot, :model_key, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[queued processing]) }

  def completed? = status == "completed"
  def active? = status.in?(%w[queued processing])
end
