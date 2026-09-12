import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["stream", "update", "results", "selectionBar"]
  static values = { url: String }

  connect() {
    this.connected = true
    // Reconcile after subscribing, including reconnects, so a completion between
    // the initial page render and the Cable subscription cannot be missed.
    this.observer = new MutationObserver(() => {
      if (this.streamTarget.hasAttribute("connected")) this.refresh()
    })
    this.observer.observe(this.streamTarget, { attributes: true, attributeFilter: ["connected"] })
    if (this.streamTarget.hasAttribute("connected")) this.refresh()
  }

  disconnect() {
    this.connected = false
    this.observer?.disconnect()
    this.request?.abort()
  }

  updateTargetConnected() {
    this.refresh()
  }

  async refresh() {
    if (!this.connected) return
    if (this.request) {
      this.refreshAgain = true
      return
    }

    this.request = new AbortController()
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/vnd.turbo-stream.html", "X-Document-List-Refresh": "true" },
        signal: this.request.signal
      })
      if (response.ok && response.headers.get("Content-Type")?.includes("text/vnd.turbo-stream.html")) {
        const html = await response.text()
        if (this.connected) window.Turbo.renderStreamMessage(html)
      }
    } catch (error) {
      // Keep the current list during a connection failure. A later processing
      // update or Cable reconnect will request the current state again.
      if (error.name !== "AbortError") this.refreshAgain = false
    } finally {
      this.request = null
      if (this.connected && this.refreshAgain) {
        this.refreshAgain = false
        this.refresh()
      }
    }
  }

  beforeRender(event) {
    if (event.target.getAttribute("target") !== this.resultsTarget.id) return

    const render = event.detail.render
    event.detail.render = async (stream) => {
      // Capture at render time: the user may have checked another row while
      // the background refresh was in flight.
      const selected = new Set(Array.from(this.resultsTarget.querySelectorAll("input:checked"), (input) => input.value))
      const active = document.activeElement
      const focusedId = this.resultsTarget.contains(active) ? active.id : null

      await render(stream)

      const checkboxes = this.resultsTarget.querySelectorAll('input[name="document_selection[]"]')
      checkboxes.forEach((checkbox) => { checkbox.checked = selected.has(checkbox.value) })
      this.selectionBarTarget.classList.toggle("hidden", checkboxes.length === 0)
      this.selectionBarTarget.classList.toggle("flex", checkboxes.length > 0)
      if (focusedId) document.getElementById(focusedId)?.focus({ preventScroll: true })
      this.dispatch("updated", { target: this.resultsTarget })
    }
  }
}
