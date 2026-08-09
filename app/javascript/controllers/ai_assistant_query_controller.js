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
    longWaitAfter: { type: Number, default: 30_000 },
    reconcileEvery: { type: Number, default: 3_000 },
    startRetryAfter: { type: Number, default: 2_000 },
    startRetryMaxAttempts: { type: Number, default: 4 }
  }

  connect() {
    this.connected = true
    this.busy = false
    this.currentQueryId = null
    this.currentPhase = null
    this.currentStatusUrl = null
    this.startUrl = null
    this.startRetryAttempts = 0
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
    this.stopReconciliation()
    this.resetStartRetry()
  }

  submit(event) {
    if (this.busy) {
      event.preventDefault()
      return
    }

    this.currentQueryId = null
    this.currentPhase = "starting"
    this.currentStatusUrl = null
    this.startUrl = null
    this.startedAt = Date.now()
    this.resetReassurance()
    this.stopReconciliation()
    this.resetStartRetry()

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
    this.stopReconciliation()
    this.stopStartRetry()
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

    if (changedQuery) {
      this.resetReassurance()
      this.resetStartRetry()
    }

    this.currentQueryId = queryId
    this.currentPhase = phase
    this.currentStatusUrl = query.dataset.statusUrl || null
    this.startUrl = query.dataset.startUrl || null
    this.startedAt = Date.parse(query.dataset.startedAt) || Date.now()
    this.setBusy(active)

    if (active && this.currentStatusUrl) {
      this.scheduleReconciliation(queryId, this.currentStatusUrl)
    } else {
      this.stopReconciliation()
    }

    if (!this.startUrl) this.resetStartRetry()

    if (announce && (changedQuery || changedPhase)) {
      this.announce(query.dataset.announcement)
    }
  }

  async startQuery(query) {
    const startUrl = query.dataset.startUrl
    if (!startUrl) return

    const queryId = query.dataset.queryId
    this.startUrl = startUrl

    if (this.startRetryTimer || this.startRequestQueryId === queryId) return

    await this.requestStart(queryId, startUrl)
  }

  async requestStart(queryId, startUrl) {
    if (!this.connected || !this.busy || queryId !== this.currentQueryId) return

    this.startRequestQueryId = queryId
    let shouldRetry = false

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

      if (!response.ok) {
        if (this.retryableStartStatus(response.status)) throw new Error("Query start failed")

        this.rejectStart(queryId)
        return
      }
      await response.text()
      if (!this.connected || queryId !== this.currentQueryId) return

      this.startUrl = null
      this.resetStartRetry()
      this.queryTargets
        .find((query) => query.dataset.queryId === queryId)
        ?.removeAttribute("data-start-url")
    } catch (_error) {
      if (!this.connected || !this.busy || queryId !== this.currentQueryId || this.startUrl !== startUrl) return

      const currentQuery = this.queryTargets.find((query) => query.dataset.queryId === queryId)
      const startStatus = currentQuery?.querySelector("[data-ai-assistant-start-status]")
      if (startStatus) startStatus.textContent = "Still getting your question started…"

      if (!this.startRetryAnnounced) {
        this.startRetryAnnounced = true
        this.announce("We’re still getting your question started. You don’t need to submit it again.")
      }

      shouldRetry = true
    } finally {
      if (this.startRequestQueryId === queryId) this.startRequestQueryId = null
      if (shouldRetry) this.scheduleStartRetry(queryId, startUrl)
    }
  }

  scheduleStartRetry(queryId, startUrl) {
    this.stopStartRetry()

    if (this.startRetryAttempts >= this.startRetryMaxAttemptsValue) {
      this.rejectStart(queryId)
      return
    }

    const retryAfter = this.startRetryAfterValue * (2 ** this.startRetryAttempts)
    this.startRetryAttempts += 1
    this.startRetryTimer = window.setTimeout(() => {
      this.startRetryTimer = undefined
      this.requestStart(queryId, startUrl)
    }, retryAfter)
  }

  stopStartRetry() {
    window.clearTimeout(this.startRetryTimer)
    this.startRetryTimer = undefined
  }

  resetStartRetry() {
    this.stopStartRetry()
    this.startRetryAttempts = 0
  }

  retryableStartStatus(status) {
    return status === 408 || status === 409 || status === 429 || status >= 500
  }

  rejectStart(queryId) {
    if (!this.connected || queryId !== this.currentQueryId) return

    this.startUrl = null
    this.currentStatusUrl = null
    this.resetStartRetry()
    this.stopReconciliation()

    const currentQuery = this.queryTargets.find((query) => query.dataset.queryId === queryId)
    if (currentQuery) {
      currentQuery.dataset.active = "false"
      currentQuery.dataset.phase = "start-failed"
      currentQuery.removeAttribute("data-start-url")
      currentQuery.removeAttribute("data-status-url")

      const startStatus = currentQuery.querySelector("[data-ai-assistant-start-status]")
      if (startStatus) startStatus.textContent = "We couldn’t start that question. Please refresh and try again."
    }

    this.currentPhase = "start-failed"
    this.setBusy(false)
    this.announce("We couldn’t start that question. Please refresh and try again.")
  }

  scheduleReconciliation(queryId, statusUrl) {
    this.stopReconciliation()
    this.reconciliationTimer = window.setTimeout(() => {
      this.reconciliationTimer = undefined
      this.reconcile(queryId, statusUrl)
    }, this.reconcileEveryValue)
  }

  stopReconciliation() {
    window.clearTimeout(this.reconciliationTimer)
    this.reconciliationTimer = undefined
  }

  async reconcile(queryId, statusUrl) {
    if (!this.connected || !this.busy || queryId !== this.currentQueryId) return

    try {
      const response = await window.fetch(statusUrl, {
        cache: "no-store",
        credentials: "same-origin",
        headers: { Accept: "text/html" }
      })

      if (!response.ok) throw new Error("Query status failed")
      const html = await response.text()
      if (!this.connected || !this.busy || queryId !== this.currentQueryId) return

      this.renderNewerQuery(queryId, html)
    } catch (_error) {
      // Cable and this status check back each other up. A later check can still recover.
    } finally {
      if (this.connected && this.busy && queryId === this.currentQueryId) {
        this.scheduleReconciliation(queryId, statusUrl)
      }
    }
  }

  renderNewerQuery(queryId, html) {
    const template = document.createElement("template")
    template.innerHTML = html.trim()
    const incomingQuery = Array.from(
      template.content.querySelectorAll("[data-ai-assistant-query-target~='query']")
    ).find((query) => query.dataset.queryId === queryId)
    const currentQuery = this.queryTargets.find((query) => query.dataset.queryId === queryId)
    if (!incomingQuery || !currentQuery) return

    const incomingVersion = incomingQuery.dataset.queryVersion
    const currentVersion = currentQuery.dataset.queryVersion
    if (!incomingVersion || (currentVersion && incomingVersion <= currentVersion)) return

    currentQuery.replaceWith(incomingQuery)
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
    this.startRetryAnnounced = false
  }
}
