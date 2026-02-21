import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

const COOKIE_NAME = "rule_agent_token"

export default class extends Controller {
  static targets = ["messages", "input", "submit", "form", "fullscreenBtn"]
  static values  = { token: String }

  connect() {
    Turbo.setProgressBarDelay(1_000_000)

    this.#persistToken()
    this.#injectToken()

    this.scrollToBottom()

    this.formTarget.addEventListener("submit", () => {
      this.submitTarget.disabled = true
    })

    this.observer = new MutationObserver(() => this.scrollToBottom())
    this.observer.observe(this.messagesTarget, { childList: true, subtree: true })
  }

  disconnect() {
    Turbo.setProgressBarDelay(500)
    document.body.classList.remove("rule-agent-fullscreen")
    this.observer?.disconnect()
  }

  submitOnEnter(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.formTarget.requestSubmit()
    }
  }

  onSubmit() {
    const text = this.inputTarget.value.trim()
    if (!text) return

    this.#removeEmpty()
    this.#appendUserBubble(text)
    this.#appendThinkingBubble()
    this.submitTarget.disabled = true
  }

  onSubmitEnd() {
    this.#removeThinkingBubble()
    this.submitTarget.disabled = false
    this.inputTarget.value = ""
    this.inputTarget.focus()
  }

  scrollToBottom() {
    const messages = this.messagesTarget
    messages.scrollTop = messages.scrollHeight
  }

  clearStorage() {
    this.#deleteCookie()
  }

  toggleFullscreen() {
    const isFullscreen = document.body.classList.toggle("rule-agent-fullscreen")
    this.fullscreenBtnTarget.textContent = isFullscreen ? "Exit Fullscreen" : "Fullscreen"
    this.scrollToBottom()
  }

  // Private

  #removeEmpty() {
    this.messagesTarget.querySelector(".rule-agent__empty")?.remove()
  }

  #appendUserBubble(text) {
    const el = document.createElement("div")
    el.className = "message message--user"
    el.innerHTML = `<div class="message__role">You</div><div class="message__content">${this.#escapeHtml(text)}</div>`
    this.messagesTarget.appendChild(el)
    this.scrollToBottom()
  }

  #appendThinkingBubble() {
    const el = document.createElement("div")
    el.className = "message message--assistant message--thinking"
    el.id = "thinking-bubble"
    el.innerHTML = `<div class="message__role">Agent</div><div class="message__content message__thinking"><span></span><span></span><span></span></div>`
    this.messagesTarget.appendChild(el)
    this.scrollToBottom()
  }

  #removeThinkingBubble() {
    document.getElementById("thinking-bubble")?.remove()
  }

  #escapeHtml(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>")
  }

  // Mirror the authoritative token (rendered by the server) into a plain cookie
  // so the browser sends it on every subsequent GET request, including page refreshes.
  #persistToken() {
    if (this.tokenValue) {
      const expires = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toUTCString()
      document.cookie = `${COOKIE_NAME}=${this.tokenValue}; path=/; expires=${expires}; SameSite=Lax`
    }
  }

  #deleteCookie() {
    document.cookie = `${COOKIE_NAME}=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax`
  }

  #injectToken() {
    // No-op: the cookie is sent automatically by the browser; no hidden field needed.
  }
}
