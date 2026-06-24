import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "modal", "recipientEmail", "selectedFields", "selectedSummary"]

  open(event) {
    event.preventDefault()

    const selectedCheckboxes = this.checkboxTargets.filter((checkbox) => checkbox.checked)
    const clickedDocument = {
      id: event.params.documentId?.toString(),
      title: event.params.documentTitle
    }
    const selectedDocuments = selectedCheckboxes.length > 0 ? selectedCheckboxes.map((checkbox) => ({
      id: checkbox.value,
      title: checkbox.dataset.documentTitle
    })) : [clickedDocument]

    this.renderSelectedDocuments(selectedDocuments)
    this.modalTarget.classList.remove("hidden")
    this.modalTarget.setAttribute("aria-hidden", "false")
    document.body.classList.add("overflow-hidden")
    this.focusRecipientField()
  }

  close(event) {
    event?.preventDefault()

    this.modalTarget.classList.add("hidden")
    this.modalTarget.setAttribute("aria-hidden", "true")
    document.body.classList.remove("overflow-hidden")
  }

  closeOnBackdrop(event) {
    if (event.target === this.modalTarget || event.target.dataset.documentShareBackdrop === "true") {
      this.close(event)
    }
  }

  keepOpen(event) {
    event.stopPropagation()
  }

  selectRecipient(event) {
    if (event.target.value) {
      this.recipientEmailTarget.value = event.target.value
      this.recipientEmailTarget.focus()
    }
  }

  closeWithKeyboard(event) {
    if (event.key === "Escape" && !this.modalTarget.classList.contains("hidden")) {
      this.close(event)
    }
  }

  disconnect() {
    document.body.classList.remove("overflow-hidden")
  }

  renderSelectedDocuments(documents) {
    this.selectedFieldsTarget.replaceChildren(
      ...documents.map((document) => {
        const input = window.document.createElement("input")
        input.type = "hidden"
        input.name = "share_event[document_ids][]"
        input.value = document.id
        return input
      })
    )

    this.selectedSummaryTarget.textContent = documents.length === 1 ? documents[0].title : `${documents.length} documents selected`
  }

  focusRecipientField() {
    this.modalTarget.querySelector("input[type='email']")?.focus()
  }
}
