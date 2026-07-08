import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["category", "dropzone", "input", "list", "summary"]
  static values = {
    categoryOptions: Array,
    emptyLabel: { type: String, default: "No files selected" }
  }

  connect() {
    this.manualCategories = new Set()
    this.sync()
  }

  changed() {
    this.sync()
  }

  categoryChanged() {
    this.listTarget.querySelectorAll("select[data-file-dropzone-file-category]").forEach((select) => {
      if (this.manualCategories.has(select.dataset.fileIndex)) return

      select.value = this.defaultCategory
    })
  }

  fileCategoryChanged(event) {
    this.manualCategories.add(event.target.dataset.fileIndex)
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

    this.inputTarget.files = event.dataTransfer.files
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  sync() {
    const files = Array.from(this.inputTarget.files || [])

    this.manualCategories = new Set([...this.manualCategories].filter((index) => Number(index) < files.length))
    this.summaryTarget.textContent = files.length === 0 ? this.emptyLabelValue : this.selectedLabel(files.length)
    this.listTarget.replaceChildren(...files.map((file, index) => this.fileItem(file, index)))
    this.listTarget.classList.toggle("hidden", files.length === 0)
  }

  selectedLabel(count) {
    return `${count} ${count === 1 ? "file" : "files"} selected`
  }

  fileItem(file, index) {
    const item = document.createElement("li")
    item.className = "grid gap-3 rounded-md border border-slate-200 bg-white px-3 py-3 text-sm sm:grid-cols-[minmax(0,1fr)_12rem] sm:items-center"

    const details = document.createElement("div")
    details.className = "min-w-0"

    const name = document.createElement("span")
    name.className = "block truncate font-medium text-slate-800"
    name.textContent = file.name

    const size = document.createElement("span")
    size.className = "mt-0.5 block text-xs text-slate-500"
    size.textContent = this.formatSize(file.size)

    details.append(name, size)
    item.append(details, this.categorySelect(index))
    return item
  }

  categorySelect(index) {
    const wrapper = document.createElement("label")
    wrapper.className = "block"

    const label = document.createElement("span")
    label.className = "mb-1 block text-xs font-medium text-slate-600"
    label.textContent = "Category"

    const select = document.createElement("select")
    select.name = "document[file_categories][]"
    select.className = "block w-full rounded-md border border-slate-300 bg-white px-2.5 py-2 text-sm text-slate-900 shadow-sm outline-none focus:border-emerald-600 focus:ring-2 focus:ring-emerald-100"
    select.dataset.fileDropzoneFileCategory = "true"
    select.dataset.fileIndex = index.toString()
    select.dataset.testid = `document-file-category-${index}`
    select.value = this.defaultCategory
    select.addEventListener("change", (event) => this.fileCategoryChanged(event))

    this.categoryOptionsValue.forEach((category) => {
      const option = document.createElement("option")
      option.value = category.value
      option.textContent = category.label
      select.append(option)
    })

    select.value = this.defaultCategory

    wrapper.append(label, select)
    return wrapper
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

  get defaultCategory() {
    return this.categoryTarget.value
  }
}
