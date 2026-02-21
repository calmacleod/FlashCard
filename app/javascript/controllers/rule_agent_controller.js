import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messages", "input", "submit", "form"]

  submitOnEnter(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.formTarget.requestSubmit()
    }
  }

  onSubmitEnd() {
    this.submitTarget.disabled = false
    this.inputTarget.value = ""
    this.inputTarget.focus()
  }

  connect() {
    this.scrollToBottom()
    // Disable submit while waiting for response
    this.formTarget.addEventListener("submit", () => {
      this.submitTarget.disabled = true
    })
    // Scroll to bottom whenever new messages are appended via Turbo
    this.observer = new MutationObserver(() => this.scrollToBottom())
    this.observer.observe(this.messagesTarget, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  scrollToBottom() {
    const messages = this.messagesTarget
    messages.scrollTop = messages.scrollHeight
  }
}
