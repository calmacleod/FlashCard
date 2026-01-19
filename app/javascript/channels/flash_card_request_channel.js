import consumer from "channels/consumer"

function subscribeToFlashCardRequest(requestId) {
  consumer.subscriptions.create(
    { channel: "FlashCardRequestChannel", request_id: requestId },
    {
      received(data) {
        if (!data || !data.html) return;
        const target = document.getElementById(`flash_card_request_${requestId}`);
        if (!target) return;
        target.innerHTML = data.html;
        document.dispatchEvent(new CustomEvent("flash-card-request:updated", { detail: { requestId } }));
      }
    }
  )
}

function bind() {
  const page = document.querySelector("[data-flash-card-request-id]");
  const requestId = page?.dataset.flashCardRequestId;
  if (!requestId) return;

  if (page.dataset.subscribed === "true") return;
  page.dataset.subscribed = "true";

  subscribeToFlashCardRequest(requestId);
}

document.addEventListener("turbo:load", bind);
document.addEventListener("DOMContentLoaded", bind);

