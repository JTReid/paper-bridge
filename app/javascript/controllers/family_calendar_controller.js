import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "closeButton", "trigger"]

  open(event) {
    this.trigger = event.currentTarget
    this.triggerTargets.forEach((trigger) => trigger.setAttribute("aria-expanded", "true"))

    if (!this.dialogTarget.open) this.dialogTarget.showModal()
    document.body.classList.add("overflow-hidden")
    this.closeButtonTarget.focus()
  }

  close(event) {
    event?.preventDefault()
    this.dialogTarget.close()
  }

  closeOnBackdrop(event) {
    if (event.target !== this.dialogTarget) return

    const bounds = this.dialogTarget.getBoundingClientRect()
    const outsideDialog = event.clientX < bounds.left || event.clientX > bounds.right ||
      event.clientY < bounds.top || event.clientY > bounds.bottom

    if (outsideDialog) this.dialogTarget.close()
  }

  restorePage() {
    document.body.classList.remove("overflow-hidden")
    this.triggerTargets.forEach((trigger) => trigger.setAttribute("aria-expanded", "false"))
    this.trigger?.focus()
  }

  expectFrameResult(event) {
    const frame = event.target.closest("turbo-frame")
    if (frame?.id === "family_calendar_frame") {
      this.frameFocusSelector = "[data-family-calendar-result-focus]"
    }
  }

  expectFrameNavigation(event) {
    const frame = event.target.closest("turbo-frame")
    if (frame?.id === "family_calendar_frame") {
      this.frameFocusSelector = "#calendar-month-heading"
    }
  }

  focusFrameUpdate(event) {
    if (!this.frameFocusSelector || event.target.id !== "family_calendar_frame") return

    const focusSelector = this.frameFocusSelector
    this.frameFocusSelector = undefined
    event.target.querySelector(focusSelector)?.focus({ preventScroll: true })
  }

  beforeCache() {
    if (this.dialogTarget.open) this.dialogTarget.close()
    document.body.classList.remove("overflow-hidden")
  }

  disconnect() {
    document.body.classList.remove("overflow-hidden")
  }
}
