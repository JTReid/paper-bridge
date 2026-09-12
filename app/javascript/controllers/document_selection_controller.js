import { Controller } from "@hotwired/stimulus"

// Tracks which document rows are checked on the documents list, shows the
// selection bar actions, and drives the bulk delete confirmation dialog.
// Sharing reuses the same checkboxes through the document-share controller.
export default class extends Controller {
  static targets = [
    "checkbox",
    "selectAll",
    "count",
    "actions",
    "deleteModal",
    "deleteFields",
    "deleteList",
    "deleteSummary",
    "deleteSubmit"
  ]

  connect() {
    this.update()
  }

  disconnect() {
    document.body.classList.remove("overflow-hidden")
  }

  update() {
    // Empty lists keep the selection bar hidden until documents are shown.
    if (!this.hasCountTarget || !this.hasActionsTarget) return

    const selected = this.selectedCheckboxes
    const total = this.checkboxTargets.length

    this.countTarget.textContent = selected.length === 0 ? "No documents selected" : `${selected.length} of ${total} selected`
    this.actionsTarget.classList.toggle("hidden", selected.length === 0)
    this.actionsTarget.classList.toggle("flex", selected.length > 0)

    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = total > 0 && selected.length === total
      this.selectAllTarget.indeterminate = selected.length > 0 && selected.length < total
    }
  }

  toggleAll(event) {
    this.checkboxTargets.forEach((checkbox) => { checkbox.checked = event.target.checked })
    this.update()
  }

  clear(event) {
    event?.preventDefault()
    this.checkboxTargets.forEach((checkbox) => { checkbox.checked = false })
    this.update()
  }

  openDelete(event) {
    event.preventDefault()

    const documents = this.selectedCheckboxes.map((checkbox) => ({
      id: checkbox.value,
      filename: checkbox.dataset.documentFilename || checkbox.dataset.documentTitle
    }))
    if (documents.length === 0) return

    this.renderDeleteDocuments(documents)
    this.deleteModalTarget.setAttribute("aria-hidden", "false")
    this.deleteModalTarget.showModal()
    document.body.classList.add("overflow-hidden")
  }

  closeDelete(event) {
    event?.preventDefault()
    if (!this.hasDeleteModalTarget) return

    this.deleteModalTarget.close()
    this.deleteModalTarget.setAttribute("aria-hidden", "true")
    document.body.classList.remove("overflow-hidden")
  }

  closeOnBackdrop(event) {
    if (event.target === this.deleteModalTarget || event.target.dataset.documentSelectionBackdrop === "true") {
      this.closeDelete(event)
    }
  }

  keepOpen(event) {
    event.stopPropagation()
  }

  get selectedCheckboxes() {
    return this.checkboxTargets.filter((checkbox) => checkbox.checked)
  }

  renderDeleteDocuments(documents) {
    this.deleteFieldsTarget.replaceChildren(
      ...documents.map((document) => {
        const input = window.document.createElement("input")
        input.type = "hidden"
        input.name = "document_selection[]"
        input.value = document.id
        return input
      })
    )

    this.deleteListTarget.replaceChildren(
      ...documents.map((document) => {
        const item = window.document.createElement("li")
        item.textContent = document.filename
        return item
      })
    )

    const label = documents.length === 1 ? "1 document" : `${documents.length} documents`
    this.deleteSummaryTarget.textContent = `Delete ${label}?`
    this.deleteSubmitTarget.value = `Delete ${label}`
  }
}
