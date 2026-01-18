class FlashCardRequest < ApplicationRecord
  STATUSES = %w[queued processing completed failed].freeze
  MAX_LOG_CHARS = 50_000

  validates :pdf_filename, :model, :embedding_model, presence: true
  validates :status, inclusion: { in: STATUSES }

  after_commit :broadcast_over_action_cable, on: [:create, :update]

  def set_step!(step, progress: nil)
    attributes = { current_step: step.to_s }
    attributes[:progress] = progress if progress
    update!(attributes)
  end

  def append_log!(message)
    timestamp = Time.current.strftime("%H:%M:%S")
    line = "[#{timestamp}] #{message.to_s.strip}\n"

    with_lock do
      combined = +""
      combined << self.log_text.to_s
      combined << line
      combined = combined[-MAX_LOG_CHARS, MAX_LOG_CHARS] if combined.length > MAX_LOG_CHARS
      update!(log_text: combined)
    end
  end

  private

  def broadcast_over_action_cable
    FlashCardRequestBroadcaster.broadcast(self)
  end
end
