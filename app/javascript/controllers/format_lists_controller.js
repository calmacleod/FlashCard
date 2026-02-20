import { Controller } from "@hotwired/stimulus"

// Converts inline lists into formatted <ol> elements.
// Handles: "a) foo b) bar", "1) foo 2) bar", "Note 1: foo Note 2: bar"
export default class extends Controller {
  // Each pattern: { re, labelGroup, stripRe, olType }
  static PATTERNS = [
    {
      re: /(?:^|(?<=\s))([a-z])\)\s/g,
      labelGroup: 1,
      stripRe: /^[a-z]\)\s*/,
      olType: "a",
      consecutive: true,
    },
    {
      re: /(?:^|(?<=\s))\(([a-z])\s?\)\s/g,
      labelGroup: 1,
      stripRe: /^\([a-z]\s?\)\s*/,
      olType: "a",
      consecutive: true,
    },
    {
      re: /(?:^|(?<=\s))(\d+)\)\s/g,
      labelGroup: 1,
      stripRe: /^\d+\)\s*/,
      olType: "1",
      consecutive: true,
    },
    {
      re: /Note\s+(\d+):\s*/g,
      labelGroup: 1,
      stripRe: /^Note\s+\d+:\s*/,
      olType: "1",
      consecutive: true,
    },
    {
      re: /(?:^|(?<=\s))(\d+)\.\s/g,
      labelGroup: 1,
      stripRe: /^\d+\.\s*/,
      olType: "1",
      consecutive: true,
    },
  ]

  connect() {
    this.#formatElement(this.element)
  }

  #formatElement(el) {
    const text = el.textContent
    for (const pattern of this.constructor.PATTERNS) {
      if (this.#tryFormat(el, text, pattern)) return
    }
  }

  #tryFormat(el, text, { re, labelGroup, stripRe, olType }) {
    re.lastIndex = 0
    const allMarkers = [...text.matchAll(re)]

    // Collect unique labels in order of first appearance
    const seen = new Set()
    const uniqueLabels = []
    for (const m of allMarkers) {
      const label = m[labelGroup]
      if (!seen.has(label)) { seen.add(label); uniqueLabels.push(label) }
    }

    if (uniqueLabels.length < 2) return false
    if (!this.#areConsecutive(uniqueLabels)) return false

    // Group all marker occurrences by label
    const byLabel = {}
    for (const m of allMarkers) {
      const l = m[labelGroup]
      ;(byLabel[l] ??= []).push(m)
    }

    // Select outermost markers: first occurrence of first label,
    // last occurrence of last label, first-valid for any middle labels.
    const markers = []
    for (let i = 0; i < uniqueLabels.length; i++) {
      const occurrences = byLabel[uniqueLabels[i]]
      let chosen
      if (i === 0) {
        chosen = occurrences[0]
      } else if (i === uniqueLabels.length - 1) {
        chosen = occurrences[occurrences.length - 1]
      } else {
        const prevIndex = markers[markers.length - 1].index
        chosen = occurrences.find(m => m.index > prevIndex)
        if (!chosen) return false
      }
      markers.push(chosen)
    }

    if (markers.length < 2) return false

    const splitPoints = markers.map(m => m.index)
    const preamble = text.slice(0, splitPoints[0]).trim()
    const listItems = splitPoints.map((start, i) => {
      const end = splitPoints[i + 1] ?? text.length
      return text.slice(start, end).replace(stripRe, "").trim()
    })

    const ol = document.createElement("ol")
    ol.type = olType
    ol.style.cssText = "margin: 0.25rem 0 0 1.5rem; line-height: 1.6;"

    listItems.forEach(item => {
      const li = document.createElement("li")
      li.textContent = item
      // Recursively format nested patterns within each list item
      this.#formatElement(li)
      ol.appendChild(li)
    })

    el.textContent = ""
    if (preamble) {
      const span = document.createElement("span")
      span.textContent = preamble + " "
      el.appendChild(span)
    }
    el.appendChild(ol)
    return true
  }

  #areConsecutive(labels) {
    if (labels.length < 2) return false
    const isNumeric = /^\d+$/.test(labels[0])
    for (let i = 1; i < labels.length; i++) {
      if (isNumeric) {
        if (parseInt(labels[i]) !== parseInt(labels[i - 1]) + 1) return false
      } else {
        if (labels[i].charCodeAt(0) !== labels[i - 1].charCodeAt(0) + 1) return false
      }
    }
    return true
  }
}
