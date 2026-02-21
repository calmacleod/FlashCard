import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "ruleNumber", "section", "article", "query"]
  static values = {
    rulesBySource:    Object,
    sectionsByRule:   Object,
    articlesBySection: Object
  }

  connect() {
    this.filterRules()
  }

  filterRules() {
    const source = this.sourceTarget.value
    const ruleSelect = this.ruleNumberTarget
    const currentRule = ruleSelect.value

    const rules = source ? (this.rulesBySourceValue[source] || []) : this.allRules()

    ruleSelect.innerHTML = `<option value="">All rules</option>` +
      rules.map(r => `<option value="${r}"${r === currentRule ? " selected" : ""}>${r}</option>`).join("")

    this.filterSections()
  }

  filterSections() {
    const rule = this.ruleNumberTarget.value
    const sectionSelect = this.sectionTarget
    const currentSection = sectionSelect.value

    const sections = rule ? (this.sectionsByRuleValue[rule] || []) : this.allSections()

    sectionSelect.innerHTML = `<option value="">All sections</option>` +
      sections.map(s => `<option value="${s}"${s === currentSection ? " selected" : ""}>${s}</option>`).join("")

    this.filterArticles()
  }

  filterArticles() {
    const section = this.sectionTarget.value
    const articleSelect = this.articleTarget
    const currentArticle = articleSelect.value

    const articles = section ? (this.articlesBySectionValue[section] || []) : this.allArticles()

    articleSelect.innerHTML = `<option value="">All articles</option>` +
      articles.map(a => `<option value="${a}"${a === currentArticle ? " selected" : ""}>${a}</option>`).join("")
  }

  clear() {
    this.queryTarget.value = ""
    this.ruleNumberTarget.value = ""
    this.sectionTarget.value = ""
    this.articleTarget.value = ""
    this.element.requestSubmit()
  }

  allRules() {
    const all = Object.values(this.rulesBySourceValue).flat()
    return [...new Set(all)].sort()
  }

  allSections() {
    const all = Object.values(this.sectionsByRuleValue).flat()
    return [...new Set(all)].sort()
  }

  allArticles() {
    const all = Object.values(this.articlesBySectionValue).flat()
    return [...new Set(all)].sort()
  }
}
