class Flashcard < ApplicationRecord
  belongs_to :document

  validates :front, :back, presence: true
  validates :position, presence: true

  scope :ordered, -> { order(:position) }
end
