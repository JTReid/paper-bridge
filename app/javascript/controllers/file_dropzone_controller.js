import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["clear", "dropzone", "error", "input", "list", "summary"]
  static values = {
    emptyLabel: { type: String, default: "No files selected" },
    maxFiles: Number
  }

  connect() {
    this.sync()
  }

  changed() {
    this.sync()
  }

  validateSubmission(event) {
    if (this.validateSelection()) return

    event.preventDefault()
    this.inputTarget.reportValidity()
  }

  remove(event) {
    const files = Array.from(this.inputTarget.files || [])
    const index = event.params.index
    if (!Number.isInteger(index) || index < 0 || index >= files.length) return

    files.splice(index, 1)
    this.setFiles(files)

    const nextButton = this.listTarget.querySelector(`[data-file-dropzone-index-param="${Math.min(index, files.length - 1)}"]`)
    const focusTarget = nextButton || this.inputTarget
    focusTarget.focus({ preventScroll: true })
  }

  clear() {
    this.setFiles([])
    this.inputTarget.focus({ preventScroll: true })
  }

  dragOver(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("border-emerald-500", "bg-emerald-50", "ring-2", "ring-emerald-100")
  }

  dragLeave() {
    this.clearDragState()
  }

  drop(event) {
    event.preventDefault()
    this.clearDragState()

    if (event.dataTransfer.files.length === 0) return

    this.setFiles(Array.from(event.dataTransfer.files))
  }

  setFiles(files) {
    const selection = new DataTransfer()
    files.forEach((file) => selection.items.add(file))

    this.inputTarget.files = selection.files
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  sync() {
    const files = Array.from(this.inputTarget.files || [])

    this.summaryTarget.textContent = files.length === 0 ? this.emptyLabelValue : this.selectedLabel(files.length)
    this.listTarget.replaceChildren(...files.map((file, index) => this.fileItem(file, index)))
    this.listTarget.classList.toggle("hidden", files.length === 0)
    this.clearTarget.classList.toggle("hidden", files.length === 0)
    this.validateSelection()
  }

  validateSelection() {
    const count = this.inputTarget.files?.length || 0
    const excess = count - this.maxFilesValue
    const error = excess > 0 ?
      `You selected ${count} files. Upload up to ${this.maxFilesValue} files at a time. Remove ${excess} ${excess === 1 ? "file" : "files"} or clear the selection.` :
      ""

    this.inputTarget.setCustomValidity(error)
    this.errorTarget.textContent = error
    this.errorTarget.classList.toggle("hidden", !error)
    if (error) {
      this.inputTarget.setAttribute("aria-invalid", "true")
    } else {
      this.inputTarget.removeAttribute("aria-invalid")
    }

    return !error
  }

  selectedLabel(count) {
    return `${count} ${count === 1 ? "file" : "files"} selected`
  }

  fileItem(file, index) {
    const item = document.createElement("li")
    item.className = "flex items-center justify-between gap-3 rounded-md border border-slate-200 bg-white px-3 py-3 text-sm"
    item.dataset.testid = "document-selected-file"

    const details = document.createElement("div")
    details.className = "min-w-0"

    const name = document.createElement("span")
    name.className = "block truncate font-medium text-slate-800"
    name.textContent = file.name

    const size = document.createElement("span")
    size.className = "mt-0.5 block text-xs text-slate-500"
    size.textContent = this.formatSize(file.size)

    details.append(name, size)
    item.append(details, this.removeButton(file, index))
    return item
  }

  removeButton(file, index) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "shrink-0 rounded-md px-3 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-100"
    button.textContent = "Remove"
    button.setAttribute("aria-label", `Remove ${file.name}`)
    button.dataset.action = "file-dropzone#remove"
    button.dataset.fileDropzoneIndexParam = index.toString()
    button.dataset.testid = `document-file-remove-${index}`
    return button
  }

  formatSize(bytes) {
    if (bytes < 1024) return `${bytes} B`

    const kilobytes = bytes / 1024
    if (kilobytes < 1024) return `${kilobytes.toFixed(1)} KB`

    return `${(kilobytes / 1024).toFixed(1)} MB`
  }

  clearDragState() {
    this.dropzoneTarget.classList.remove("border-emerald-500", "bg-emerald-50", "ring-2", "ring-emerald-100")
  }
}
