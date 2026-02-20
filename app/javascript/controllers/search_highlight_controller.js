import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { query: String }

  connect() {
    const words = this.queryValue
      .split(/\s+/)
      .map(w => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
      .filter(w => w.length > 2)

    if (words.length === 0) return

    const pattern = new RegExp(`(${words.join("|")})`, "gi")
    this.#highlightTextNodes(this.element, pattern)
  }

  #highlightTextNodes(node, pattern) {
    if (node.nodeType === Node.TEXT_NODE) {
      if (!pattern.test(node.textContent)) return
      pattern.lastIndex = 0

      const frag = document.createDocumentFragment()
      let last = 0
      let match

      while ((match = pattern.exec(node.textContent)) !== null) {
        if (match.index > last) {
          frag.appendChild(document.createTextNode(node.textContent.slice(last, match.index)))
        }
        const mark = document.createElement("mark")
        mark.className = "search-highlight"
        mark.textContent = match[0]
        frag.appendChild(mark)
        last = pattern.lastIndex
      }

      if (last < node.textContent.length) {
        frag.appendChild(document.createTextNode(node.textContent.slice(last)))
      }

      node.replaceWith(frag)
    } else if (node.nodeType === Node.ELEMENT_NODE && node.nodeName !== "MARK") {
      Array.from(node.childNodes).forEach(child => this.#highlightTextNodes(child, pattern))
    }
  }
}
