import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card", "counter", "dots"]
  static values  = { total: Number }

  connect() {
    this.current = 0
    this.flipped  = false
    this.updateDisplay()
  }

  flip() {
    const card = this.activeCard()
    if (!card) return
    card.classList.toggle("fc-card--flipped")
    this.flipped = card.classList.contains("fc-card--flipped")
  }

  next() {
    if (this.current < this.totalValue - 1) {
      this.go(this.current + 1)
    }
  }

  prev() {
    if (this.current > 0) {
      this.go(this.current - 1)
    }
  }

  go(index) {
    this.activeCard()?.classList.remove("fc-card--active", "fc-card--flipped")
    this.current = index
    this.flipped = false
    this.updateDisplay()
  }

  updateDisplay() {
    this.cardTargets.forEach((card, i) => {
      card.classList.toggle("fc-card--active", i === this.current)
      if (i !== this.current) card.classList.remove("fc-card--flipped")
    })

    if (this.hasCounterTarget) {
      this.counterTarget.textContent = this.current + 1
    }

    if (this.hasDotsTarget) {
      this.dotsTarget.querySelectorAll(".fc-dot").forEach((dot, i) => {
        dot.classList.toggle("fc-dot--active", i === this.current)
      })
    }
  }

  activeCard() {
    return this.cardTargets[this.current]
  }
}
