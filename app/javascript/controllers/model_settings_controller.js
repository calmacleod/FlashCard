import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["model", "effortField", "effort", "budgetField", "budget", "hint"]
  static values = { configurations: Object }

  connect() {
    this.refresh()
  }

  refresh() {
    const config = this.configurationsValue[this.modelTarget.value] || { mode: "none", efforts: [] }
    const effortMode = config.mode === "effort"
    const budgetMode = config.mode === "budget"

    this.effortFieldTarget.hidden = !effortMode
    this.budgetFieldTarget.hidden = !budgetMode
    this.effortTarget.disabled = !effortMode
    this.budgetTarget.disabled = !budgetMode

    if (effortMode) {
      const previous = this.effortTarget.value
      this.effortTarget.replaceChildren(new Option("Provider default", ""))
      config.efforts.forEach(value => this.effortTarget.add(new Option(value, value)))
      this.effortTarget.value = config.efforts.includes(previous) ? previous : ""
    }

    this.hintTarget.textContent = config.hint || {
      effort: "This model uses named reasoning-effort levels.",
      budget: "This model uses a numeric thinking-token budget.",
      none: "RubyLLM does not advertise a compatible thinking control for this model."
    }[config.mode]
  }
}
