import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "announcer",
    "elapsed",
    "input",
    "optimistic",
    "query",
    "region",
    "result",
    "submitter"
  ]

  static values = {
    reassureAfter: { type: Number, default: 10_000 },
    longWaitAfter: { type: Number, default: 30_000 }
  }

  connect() {
    this.connected = true
    this.busy = false
    this.currentQueryId = null
    this.currentPhase = null
    this.resetReassurance()

    if (this.hasQueryTarget) {
      this.syncFromQuery(this.queryTarget, false)
      this.startQuery(this.queryTarget)
    } else {
      this.setBusy(false)
    }
  }

  disconnect() {
    this.connected = false
    this.stopClock()
  }

  submit(event) {
    if (this.busy) {
      event.preventDefault()
      return
    }

    this.currentQueryId = null
    this.currentPhase = "starting"
    this.startedAt = Date.now()
    this.resetReassurance()

    this.optimisticTarget.hidden = false
    this.resultTarget.hidden = true
    this.setBusy(true)
    this.announce("Starting your question.")
  }

  submitEnd(event) {
    if (event.detail.success) return

    this.optimisticTarget.hidden = true
    this.resultTarget.hidden = false
    this.setBusy(false)
    this.announce("We couldn’t start that question. Please try again.")
  }

  queryTargetConnected(query) {
    if (!this.connected) return

    this.optimisticTarget.hidden = true
    this.resultTarget.hidden = false
    this.syncFromQuery(query, true)
    this.startQuery(query)
  }

  submitterTargetConnected(submitter) {
    submitter.disabled = Boolean(this.busy)
  }

  inputTargetConnected(input) {
    input.readOnly = Boolean(this.busy)
  }

  beforeCache() {
    this.stopClock()
    this.busy = false
    this.optimisticTarget.hidden = true
    this.resultTarget.hidden = false
    this.setControlsDisabled(false)
    this.regionTarget.setAttribute("aria-busy", "false")
  }

  syncFromQuery(query, announce) {
    const queryId = query.dataset.queryId
    const phase = query.dataset.phase
    const active = query.dataset.active === "true"
    const changedQuery = queryId !== this.currentQueryId
    const changedPhase = phase !== this.currentPhase

    if (changedQuery) this.resetReassurance()

    this.currentQueryId = queryId
    this.currentPhase = phase
    this.startedAt = Date.parse(query.dataset.startedAt) || Date.now()
    this.setBusy(active)

    if (announce && (changedQuery || changedPhase)) {
      this.announce(query.dataset.announcement)
    }
  }

  async startQuery(query) {
    const startUrl = query.dataset.startUrl
    if (!startUrl) return

    query.removeAttribute("data-start-url")

    try {
      const response = await window.fetch(startUrl, {
        method: "POST",
        credentials: "same-origin",
        keepalive: true,
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        }
      })

      if (!response.ok) throw new Error("Query start failed")
      await response.text()
    } catch (_error) {
      if (!this.connected || !query.isConnected || query.dataset.queryId !== this.currentQueryId) return

      const startStatus = query.querySelector("[data-ai-assistant-start-status]")
      if (startStatus) startStatus.textContent = "We couldn’t start that question. Please refresh and try again."
      this.setBusy(false)
      this.announce("We couldn’t start that question. Please refresh and try again.")
    }
  }

  setBusy(busy) {
    this.busy = busy
    this.regionTarget.setAttribute("aria-busy", busy.toString())
    this.setControlsDisabled(busy)

    if (busy) {
      this.startClock()
    } else {
      this.stopClock()
    }
  }

  setControlsDisabled(disabled) {
    this.submitterTargets.forEach((submitter) => {
      submitter.disabled = disabled
    })

    this.inputTargets.forEach((input) => {
      input.readOnly = disabled
    })
  }

  startClock() {
    if (this.clock) return

    this.elapsedTarget.hidden = false
    this.tick()
    this.clock = window.setInterval(() => this.tick(), 1_000)
  }

  stopClock() {
    window.clearInterval(this.clock)
    this.clock = undefined
    this.elapsedTarget.textContent = ""
    this.elapsedTarget.hidden = true
  }

  tick() {
    const elapsedMs = Math.max(0, Date.now() - this.startedAt)
    const seconds = Math.floor(elapsedMs / 1_000)

    if (elapsedMs >= this.longWaitAfterValue) {
      this.elapsedTarget.textContent = "Still working — you can leave this page and PaperBridge will keep going."
    } else if (seconds >= 5) {
      this.elapsedTarget.textContent = `${seconds} seconds so far`
    } else {
      this.elapsedTarget.textContent = "Just started"
    }

    if (elapsedMs >= this.longWaitAfterValue && !this.longWaitAnnounced) {
      this.longWaitAnnounced = true
      this.announce("This is taking longer than usual. You can leave this page; PaperBridge will keep working.")
    } else if (elapsedMs >= this.reassureAfterValue && !this.reassuranceAnnounced) {
      this.reassuranceAnnounced = true
      this.announce("Still working. Bigger questions can take around 30 seconds.")
    }
  }

  announce(message) {
    if (!message) return

    this.announcerTarget.textContent = message
  }

  resetReassurance() {
    this.reassuranceAnnounced = false
    this.longWaitAnnounced = false
  }
}
