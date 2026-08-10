class ApplicationSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.value_for(key, default: nil)
    find_by(key:)&.value || default
  end

  def self.write(key, value)
    setting = find_or_initialize_by(key:)
    setting.update!(value:)
    value
  end
end
