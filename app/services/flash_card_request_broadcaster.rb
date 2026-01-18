class FlashCardRequestBroadcaster
  def self.broadcast(request)
    html = ApplicationController.render(
      partial: "flash_cards/request_panel",
      locals: {
        flash_card_request: request,
        prompt_text: request.prompt_text
      }
    )

    ActionCable.server.broadcast(
      "flash_card_request:#{request.id}",
      {
        request_id: request.id,
        html:
      }
    )
  end
end
