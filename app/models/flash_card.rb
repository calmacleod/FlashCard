class FlashCard < ApplicationRecord
  belongs_to :flash_card_request

  STATUSES = %w[kept changed discarded].freeze

  validates :front, :back, presence: true
  validates :status, inclusion: { in: STATUSES }, if: :refinement_columns_present?

  def effective_front
    status_value == "changed" ? refined_front.to_s : front.to_s
  end

  def effective_back
    status_value == "changed" ? refined_back.to_s : back.to_s
  end

  def status_value
    return "kept" unless refinement_columns_present?
    self[:status].to_s
  end

  private

  def refinement_columns_present?
    self.class.column_names.include?("status")
  end
end
