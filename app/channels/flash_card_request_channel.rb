class FlashCardRequestChannel < ApplicationCable::Channel
  def subscribed
    request_id = params[:request_id].to_s
    return reject if request_id.empty?

    stream_from "flash_card_request:#{request_id}"
  end
end
