class RulebookEntry < ApplicationRecord
  validates :source_csv, :text, :entry_index, presence: true

  scope :for_csv, ->(path) { where(source_csv: File.expand_path(path)).order(:entry_index) }
end
