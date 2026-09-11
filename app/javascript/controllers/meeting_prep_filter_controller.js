import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query", "entry", "count", "empty", "clear"]

  connect() {
    this.filter()
  }

  filter() {
    const query = this.queryTarget.value.trim().toLowerCase()
    let visibleCount = 0

    this.entryTargets.forEach((entry) => {
      const text = entry.dataset.meetingPrepFilterSearchText.toLowerCase()
      const matches = text.includes(query)
      entry.hidden = !matches
      if (matches) visibleCount += 1
    })

    const totalCount = this.entryTargets.length
    this.countTarget.textContent = `${visibleCount} of ${totalCount} saved ${totalCount === 1 ? "answer" : "answers"}`
    this.emptyTarget.hidden = visibleCount !== 0 || totalCount === 0
    this.clearTarget.hidden = query.length === 0
  }

  clear() {
    this.queryTarget.value = ""
    this.filter()
    this.queryTarget.focus()
  }
}
