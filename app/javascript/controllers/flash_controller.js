import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    timeout: { type: Number, default: 4500 }
  }

  connect() {
    this.timeout = window.setTimeout(() => this.dismiss(), this.timeoutValue)
  }

  disconnect() {
    window.clearTimeout(this.timeout)
  }

  dismiss() {
    this.element.classList.add("opacity-0", "-translate-y-2")
    window.setTimeout(() => this.element.remove(), 180)
  }
}
