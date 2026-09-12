import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "title", "details", "description", "scheduledAt", "dependent", "closeButton", "appointmentId", "recipientEmail", "editButton", "editForm", "editErrors", "deleteForm"]
  static values = { editingId: String }

  connect() {
    if (!this.editingIdValue) return

    const trigger = Array.from(this.element.querySelectorAll("[data-appointment-dialog-appointment-id-param]"))
      .find((button) => button.dataset.appointmentDialogAppointmentIdParam === this.editingIdValue && button.getClientRects().length)
    if (!trigger) return

    this.loadAppointment(trigger)
    this.showEditor()
    this.dialogTarget.showModal()
    this.editErrorsTarget.focus()
    this.editingIdValue = ""
  }

  open(event) {
    event.preventDefault()
    this.loadAppointment(event.currentTarget)
    this.showDetails()
    this.dialogTarget.showModal()
    this.closeButtonTarget.focus()
  }

  loadAppointment(trigger) {
    this.trigger = trigger
    this.appointmentIdTarget.value = trigger.dataset.appointmentDialogAppointmentIdParam ?? ""
    this.recipientEmailTarget.value = ""
    this.descriptionTarget.textContent = trigger.dataset.appointmentDialogDescriptionParam ?? ""
    this.scheduledAtTarget.textContent = trigger.dataset.appointmentDialogScheduledAtParam ?? ""
    this.dependentTarget.textContent = trigger.dataset.appointmentDialogDependentParam ?? ""
    this.editFormTarget.action = trigger.dataset.appointmentDialogUrlParam
    this.deleteFormTarget.action = trigger.dataset.appointmentDialogUrlParam
  }

  edit() {
    const fields = this.editFormTarget.elements
    fields.namedItem("appointment[dependent_id]").value = this.trigger.dataset.appointmentDialogDependentIdParam
    fields.namedItem("appointment[scheduled_at]").value = this.trigger.dataset.appointmentDialogLocalTimeParam
    fields.namedItem("appointment[description]").value = this.trigger.dataset.appointmentDialogDescriptionParam
    this.editErrorsTarget.hidden = true
    this.showEditor()
    fields.namedItem("appointment[dependent_id]").focus()
  }

  showEditor() {
    this.titleTarget.textContent = "Edit appointment"
    this.detailsTarget.hidden = true
    this.editFormTarget.hidden = false
  }

  showDetails() {
    this.titleTarget.textContent = "Appointment"
    this.editFormTarget.hidden = true
    this.detailsTarget.hidden = false
  }

  cancelEdit() {
    this.showDetails()
    this.editButtonTarget.focus()
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
    if (this.trigger?.isConnected && this.trigger.getClientRects().length) {
      this.trigger.focus()
    } else {
      this.element.querySelector("#calendar-month-heading")?.focus()
    }
  }
}
