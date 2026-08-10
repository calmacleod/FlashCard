import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query", "record", "empty"]

  filter() {
    const query = this.queryTarget.value.trim().toLowerCase()
    let visible = 0

    this.recordTargets.forEach((record) => {
      const matches = !query || record.dataset.searchText.includes(query)
      record.hidden = !matches
      if (matches) visible += 1
    })

    this.emptyTarget.hidden = visible > 0
  }

  expandAll() {
    this.visibleRecords().forEach((record) => { record.open = true })
  }

  collapseAll() {
    this.visibleRecords().forEach((record) => { record.open = false })
  }

  visibleRecords() {
    return this.recordTargets.filter((record) => !record.hidden)
  }
}
