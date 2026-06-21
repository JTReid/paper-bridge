import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "content", "showLabel", "hideLabel"]
  static values = {
    expanded: { type: Boolean, default: false }
  }

  connect() {
    this.sync()
  }

  toggle() {
    this.expandedValue = !this.expandedValue
  }

  expandedValueChanged() {
    this.sync()
  }

  sync() {
    const expanded = this.expandedValue

    this.contentTarget.hidden = !expanded
    this.buttonTarget.setAttribute("aria-expanded", expanded.toString())
    this.showLabelTarget.hidden = expanded
    this.hideLabelTarget.hidden = !expanded
  }
}
