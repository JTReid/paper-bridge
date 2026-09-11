import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["workspace", "status", "message", "pickerForm", "pickerQuery", "pickerClear", "choices", "choice", "pickerEmpty", "selectionCount", "addButton"]

  connect() {
    this.busy = false
    this.filterPicker()
    this.announceResult()
  }

  filterPicker() {
    const query = this.pickerQueryTarget.value.trim().toLowerCase()
    let matches = 0
    this.choiceTargets.forEach((choice) => {
      choice.hidden = !choice.dataset.searchText.includes(query)
      if (!choice.hidden) matches += 1
    })
    this.pickerEmptyTarget.hidden = matches > 0 || this.choiceTargets.length === 0
    this.pickerClearTarget.hidden = query.length === 0
    this.selectionChanged()
  }

  clearPicker() {
    this.pickerQueryTarget.value = ""
    this.filterPicker()
    this.pickerQueryTarget.focus()
  }

  selectionChanged() {
    const count = this.pickerFormTarget.querySelectorAll('input[type="checkbox"]:checked').length
    this.selectionCountTarget.textContent = `${count} selected`
    this.addButtonTarget.textContent = count ? `Add ${count} ${count === 1 ? "answer" : "answers"}` : "Add answers"
    this.addButtonTarget.setAttribute("aria-disabled", String(count === 0 || this.busy))
  }

  submit(event) {
    if (this.busy) {
      event.preventDefault()
      return
    }
    if (event.target === this.pickerFormTarget && !event.target.querySelector('input[type="checkbox"]:checked')) {
      event.preventDefault()
      this.statusTarget.textContent = "Select at least one answer to add."
    }
  }

  submitStart(event) {
    this.busy = true
    this.submitterId = event.detail.formSubmission.submitter?.id
    this.workspaceTarget.setAttribute("aria-busy", "true")
    this.selectionChanged()
  }

  submitEnd(event) {
    if (!this.renderingStream) this.finishSubmission()
    this.selectionChanged()
    if (!event.detail.fetchResponse) {
      this.statusTarget.textContent = "We couldn’t save that change. Please try again."
    }
  }

  beforeCache() {
    this.busy = false
    this.workspaceTarget.removeAttribute("aria-busy")
  }

  beforeStreamRender(event) {
    const stream = event.target
    if (stream.target !== this.workspaceTarget.id) return

    this.renderingStream = true

    const render = event.detail.render
    event.detail.render = async (element) => {
      if (!this.element.isConnected) return
      const state = this.captureState()
      this.restoreContentState(element.templateElement.content, state)
      await render(element)
      this.filterPicker()
      this.announceResult()
      this.choicesTarget.scrollTop = state.choicesScroll
      this.restoreFocus(state)
      window.scrollTo({ left: state.scrollX, top: state.scrollY, behavior: "instant" })
      this.renderingStream = false
      this.finishSubmission()
    }
  }

  finishSubmission() {
    this.busy = false
    this.workspaceTarget.removeAttribute("aria-busy")
    this.selectionChanged()
  }

  announceResult() {
    this.statusTarget.textContent = this.messageTarget.textContent
    this.statusTarget.classList.toggle("text-red-700", this.messageTarget.dataset.error === "true")
    this.statusTarget.classList.toggle("text-muted-foreground", this.messageTarget.dataset.error !== "true")
  }

  captureState() {
    const focused = document.activeElement === document.body && this.submitterId ? document.getElementById(this.submitterId) || document.activeElement : document.activeElement
    const entry = focused.closest('[data-meeting-prep-filter-target="entry"]')
    const visibleEntries = Array.from(this.workspaceTarget.querySelectorAll('[data-meeting-prep-filter-target="entry"]')).filter((item) => !item.hidden)
    const index = visibleEntries.indexOf(entry)
    const neighbor = visibleEntries[index + 1] || visibleEntries[index - 1]

    return {
      pickerQuery: this.pickerQueryTarget.value,
      meetingQuery: this.workspaceTarget.querySelector('[data-meeting-prep-filter-target="query"]').value,
      selected: new Set(Array.from(this.pickerFormTarget.querySelectorAll('input[type="checkbox"]:checked'), (input) => input.value)),
      openDetails: new Set(Array.from(this.workspaceTarget.querySelectorAll("details[open][id]"), (details) => details.id)),
      openSources: new Set(Array.from(this.workspaceTarget.querySelectorAll('[data-citations-toggle-target="button"][aria-expanded="true"]'), (button) => button.getAttribute("aria-controls"))),
      choicesScroll: this.choicesTarget.scrollTop,
      focusId: this.workspaceTarget.contains(focused) ? focused.id : null,
      fallbackId: entry?.querySelector("summary").id,
      neighborId: neighbor?.querySelector("summary").id,
      scrollX: window.scrollX,
      scrollY: window.scrollY
    }
  }

  restoreContentState(content, state) {
    content.querySelector('[data-meeting-prep-target="pickerQuery"]').value = state.pickerQuery
    content.querySelector('[data-meeting-prep-filter-target="query"]').value = state.meetingQuery
    content.querySelectorAll('input[type="checkbox"]').forEach((input) => { input.checked = state.selected.has(input.value) })
    content.querySelectorAll("details[id]").forEach((details) => { details.open = state.openDetails.has(details.id) })
    content.querySelectorAll('[data-citations-toggle-target="content"]').forEach((source) => {
      if (!state.openSources.has(source.id)) return
      const toggle = source.closest('[data-controller="citations-toggle"]')
      toggle.dataset.citationsToggleExpandedValue = "true"
      source.hidden = false
      toggle.querySelector('[data-citations-toggle-target="button"]').setAttribute("aria-expanded", "true")
      toggle.querySelector('[data-citations-toggle-target="showLabel"]').hidden = true
      toggle.querySelector('[data-citations-toggle-target="hideLabel"]').hidden = false
    })
    const query = state.meetingQuery.trim().toLowerCase()
    content.querySelectorAll('[data-meeting-prep-filter-target="entry"]').forEach((entry) => {
      entry.hidden = !entry.dataset.meetingPrepFilterSearchText.includes(query)
    })
  }

  restoreFocus(state) {
    if (!state.focusId) return
    const target = [state.focusId, state.fallbackId, state.neighborId, "meeting-prep-filter"]
      .map((id) => id && document.getElementById(id))
      .find((element) => element && !element.disabled && !element.closest("[hidden]"))
    target?.focus({ preventScroll: true })
  }
}
