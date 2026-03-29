import { Controller } from "@hotwired/stimulus"

const SCALAR_TYPES = ["string", "integer", "number", "boolean"]
const PROPERTY_TYPES = [...SCALAR_TYPES, "object", "array"]
const ITEMS_TYPES = [...SCALAR_TYPES, "object"]

export default class extends Controller {
  static targets = ["rows", "output", "additionalProperties"]

  connect() {
    const json = this.outputTarget.value.trim()
    if (!json) return
    try {
      const schema = JSON.parse(json)
      if (schema?.type === "object") {
        this.additionalPropertiesTarget.checked = schema.additionalProperties === true
        this.#loadGroup(this.rowsTarget, schema)
        this.render()
      }
    } catch (_) { /* invalid JSON — leave textarea editable */ }
  }

  addProperty(event) {
    event.stopPropagation()
    const group = event.currentTarget.closest(".schema-group")
    const footer = group.querySelector(":scope > .schema-group__footer")
    const row = document.createElement("div")
    row.className = "schema-row"
    row.innerHTML = this.#rowHTML({ name: "", type: "string", items: "string", required: true })
    group.insertBefore(row, footer)
    row.querySelector(".schema-row__name").focus()
    this.render()
  }

  removeProperty(event) {
    event.stopPropagation()
    event.currentTarget.closest(".schema-row").remove()
    this.render()
  }

  typeChanged(event) {
    event.stopPropagation()
    const row = event.currentTarget.closest(".schema-row")
    this.#syncRowVisibility(row, event.currentTarget.value)
    this.render()
  }

  itemsTypeChanged(event) {
    event.stopPropagation()
    const row = event.currentTarget.closest(".schema-row")
    row.querySelector(":scope > .schema-row__nested").hidden = event.currentTarget.value !== "object"
    this.render()
  }

  render() {
    this.outputTarget.value = JSON.stringify(
      this.#serializeGroup(this.rowsTarget, true),
      null,
      2
    )
  }

  // ── Private ────────────────────────────────────────────────────────────────

  #serializeGroup(groupEl, isRoot = false) {
    const properties = {}
    const required = []

    groupEl.querySelectorAll(":scope > .schema-row").forEach(row => {
      const name = row.querySelector(":scope > .schema-row__fields .schema-row__name").value.trim()
      if (!name) return

      const type = row.querySelector(":scope > .schema-row__fields .schema-row__type").value
      const isRequired = row.querySelector(":scope > .schema-row__fields .schema-row__required").checked

      if (type === "object") {
        properties[name] = this.#serializeGroup(row.querySelector(":scope > .schema-row__nested"))
      } else if (type === "array") {
        const itemsType = row.querySelector(".schema-row__items-type").value
        properties[name] = itemsType === "object"
          ? { type: "array", items: this.#serializeGroup(row.querySelector(":scope > .schema-row__nested")) }
          : { type: "array", items: { type: itemsType } }
      } else {
        properties[name] = { type }
      }

      if (isRequired) required.push(name)
    })

    return {
      type: "object",
      properties,
      ...(required.length > 0 ? { required } : {}),
      additionalProperties: isRoot ? this.additionalPropertiesTarget.checked : false
    }
  }

  #loadGroup(groupEl, schema) {
    const props = schema.properties || {}
    const reqd = Array.isArray(schema.required) ? schema.required : []
    const footer = groupEl.querySelector(":scope > .schema-group__footer")

    Object.entries(props).forEach(([name, propDef]) => {
      const type = propDef.type || "string"
      const itemsType = type === "array" ? (propDef.items?.type || "string") : "string"
      const isRequired = reqd.includes(name)

      const row = document.createElement("div")
      row.className = "schema-row"
      row.innerHTML = this.#rowHTML({ name, type, items: itemsType, required: isRequired })
      groupEl.insertBefore(row, footer)

      const nested = row.querySelector(":scope > .schema-row__nested")
      if (type === "object") {
        nested.hidden = false
        this.#loadGroup(nested, propDef)
      } else if (type === "array" && itemsType === "object") {
        nested.hidden = false
        this.#loadGroup(nested, propDef.items)
      }
    })
  }

  #syncRowVisibility(row, type, itemsType = null) {
    const itemsWrap = row.querySelector(":scope > .schema-row__fields .schema-row__items-wrap")
    const nested = row.querySelector(":scope > .schema-row__nested")
    itemsWrap.hidden = type !== "array"
    if (type === "object") {
      nested.hidden = false
    } else if (type === "array") {
      const it = itemsType ?? row.querySelector(".schema-row__items-type").value
      nested.hidden = it !== "object"
    } else {
      nested.hidden = true
    }
  }

  #rowHTML({ name, type, items, required }) {
    const typeOpts = PROPERTY_TYPES.map(t =>
      `<option value="${t}"${t === type ? " selected" : ""}>${t}</option>`
    ).join("")

    const itemsOpts = ITEMS_TYPES.map(t =>
      `<option value="${t}"${t === items ? " selected" : ""}>${t}</option>`
    ).join("")

    const nestedHidden = (type === "object" || (type === "array" && items === "object")) ? "" : " hidden"

    return `
      <div class="schema-row__fields">
        <input type="text" class="schema-row__name" placeholder="name"
          value="${this.#esc(name)}" data-action="input->schema-builder#render" />
        <select class="schema-row__type" data-action="change->schema-builder#typeChanged">
          ${typeOpts}
        </select>
        <div class="schema-row__items-wrap"${type !== "array" ? " hidden" : ""}>
          <span class="schema-row__items-label">items:</span>
          <select class="schema-row__items-type" data-action="change->schema-builder#itemsTypeChanged">
            ${itemsOpts}
          </select>
        </div>
        <label class="schema-row__required-label">
          <input type="checkbox" class="schema-row__required"
            ${required ? "checked" : ""} data-action="change->schema-builder#render" />
          required
        </label>
        <button type="button" class="btn btn--ghost btn--sm schema-row__remove"
          data-action="click->schema-builder#removeProperty">Remove</button>
      </div>
      <div class="schema-group schema-row__nested"${nestedHidden}>
        <div class="schema-group__footer">
          <button type="button" class="btn btn--ghost btn--sm"
            data-action="click->schema-builder#addProperty">+ Add property</button>
        </div>
      </div>
    `
  }

  #esc(str) {
    return str.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;")
  }
}
