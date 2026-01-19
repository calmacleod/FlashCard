function safeGetItem(key) {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function safeSetItem(key, value) {
  try {
    localStorage.setItem(key, value);
  } catch {
    // ignore
  }
}

function storageKey(requestId, collapsibleKey) {
  return `cards.request.${requestId}.details.${collapsibleKey}.open`;
}

function updateHint(details) {
  const hint = details.querySelector("[data-summary-hint]");
  if (!hint) return;
  hint.textContent = details.open ? "Collapse" : "Expand";
}

function initDetails(details, requestId) {
  const collapsibleKey = details.dataset.collapsibleKey;
  if (!collapsibleKey) return;

  // Restore saved state
  const saved = safeGetItem(storageKey(requestId, collapsibleKey));
  if (saved === "true") details.open = true;
  if (saved === "false") details.open = false;

  updateHint(details);

  if (details.dataset.bound === "true") return;
  details.dataset.bound = "true";

  details.addEventListener("toggle", () => {
    safeSetItem(storageKey(requestId, collapsibleKey), details.open ? "true" : "false");
    updateHint(details);
  });
}

function refreshForRequest(requestId) {
  const target = document.getElementById(`flash_card_request_${requestId}`);
  if (!target) return;

  target.querySelectorAll("details[data-collapsible-key]").forEach((details) => {
    initDetails(details, requestId);
  });
}

function bind() {
  const page = document.querySelector("[data-flash-card-request-id]");
  const requestId = page?.dataset.flashCardRequestId;
  if (!requestId) return;

  refreshForRequest(requestId);
}

document.addEventListener("turbo:load", bind);
document.addEventListener("DOMContentLoaded", bind);
document.addEventListener("flash-card-request:updated", (event) => {
  const requestId = event?.detail?.requestId;
  if (!requestId) return;
  refreshForRequest(requestId);
});

