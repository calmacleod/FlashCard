import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "body"]
  static values  = { url: String }

  connect() {
    this.element.addEventListener("click", this.#handleLinkClick)
  }

  disconnect() {
    this.element.removeEventListener("click", this.#handleLinkClick)
  }

  close() {
    this.modalTarget.setAttribute("aria-hidden", "true")
    this.bodyTarget.innerHTML = '<p class="rule-preview__loading">Loading…</p>'
  }

  // Private

  #handleLinkClick = (event) => {
    const link = event.target.closest('a[href*="rule_search/search"]')
    if (!link) return

    event.preventDefault()

    const href = link.getAttribute("href")
    const params = new URL(href, window.location.origin).searchParams
    const preview = new URL(this.urlValue, window.location.origin)

    for (const [key, value] of params.entries()) {
      preview.searchParams.set(key, value)
    }

    this.modalTarget.setAttribute("aria-hidden", "false")
    this.bodyTarget.innerHTML = '<p class="rule-preview__loading">Loading…</p>'

    fetch(preview.toString(), { headers: { "Accept": "text/html" } })
      .then(r => r.text())
      .then(html => { this.bodyTarget.innerHTML = html })
      .catch(() => { this.bodyTarget.innerHTML = '<p class="rule-preview__empty">Failed to load rule.</p>' })
  }
}
