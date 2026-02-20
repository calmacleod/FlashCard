import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "ruleNumber", "query"]
  static values = { rulesBySource: Object }

  connect() {
    this.filterRules()
  }

  filterRules() {
    const source = this.sourceTarget.value
    const ruleSelect = this.ruleNumberTarget
    const currentValue = ruleSelect.value

    const rules = source ? (this.rulesBySourceValue[source] || []) : this.allRules()

    ruleSelect.innerHTML = `<option value="">All rules</option>` +
      rules.map(r => `<option value="${r}"${r === currentValue ? " selected" : ""}>${r}</option>`).join("")
  }

  clear() {
    this.queryTarget.value = ""
    this.ruleNumberTarget.value = ""
    this.element.requestSubmit()
  }

  allRules() {
    const all = Object.values(this.rulesBySourceValue).flat()
    return [...new Set(all)].sort()
  }
}
