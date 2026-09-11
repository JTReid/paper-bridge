import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["recipientEmail"]
  static values = { triggerId: String }

  connect() {
    this.element.showModal()
    this.element.querySelector("[autofocus]")?.focus()
  }

  disconnect() {
    this.element.close()
  }

  close() {
    this.element.close()
  }

  restoreFocus() {
    if (this.element.isConnected) {
      document.getElementById(this.triggerIdValue)?.focus({ preventScroll: true })
    }
  }

  selectRecipient(event) {
    if (!event.target.value) return

    this.recipientEmailTarget.value = event.target.value
    this.recipientEmailTarget.focus()
  }
}
