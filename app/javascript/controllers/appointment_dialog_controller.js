import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "description", "scheduledAt", "dependent", "closeButton", "appointmentId", "recipientEmail"]

  open(event) {
    event.preventDefault()
    const trigger = event.currentTarget

    this.trigger = trigger
    this.appointmentIdTarget.value = trigger.dataset.appointmentDialogAppointmentIdParam ?? ""
    this.recipientEmailTarget.value = ""
    this.descriptionTarget.textContent = trigger.dataset.appointmentDialogDescriptionParam ?? ""
    this.scheduledAtTarget.textContent = trigger.dataset.appointmentDialogScheduledAtParam ?? ""
    this.dependentTarget.textContent = trigger.dataset.appointmentDialogDependentParam ?? ""
    this.dialogTarget.showModal()
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

  restoreFocus() {
    this.trigger?.focus()
  }
}
