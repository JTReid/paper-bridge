import { Controller } from "@hotwired/stimulus"
import { driver } from "driver.js"

const TOUR_VERSION = 1
const ACTIVE_STATUS = "active"

const STEP_CONTENT = {
  create_profile: {
    selector: '[data-tour="create-profile"]',
    title: "Create your first Profile",
    description: "Profiles keep one person’s records and answers together. Select Add Profile to get started.",
    number: 1,
    side: "bottom",
    align: "end"
  },
  open_profile: {
    selector: '[data-tour="open-profile"]',
    title: "Open a Profile",
    description: "Open the highlighted Profile to continue the setup tour.",
    number: 1,
    side: "bottom",
    align: "start"
  },
  profile_form: {
    selector: '[data-tour="profile-form"]',
    title: "Add their details",
    description: "Their first name is required. Everything else is optional. Save the Profile when you’re ready.",
    number: 1,
    side: "right",
    align: "start",
    actionLabel: "Add details",
    focusSelector: "#dependent_first_name"
  },
  open_documents: {
    selector: '[data-tour="open-documents"]',
    title: "Open Documents",
    description: "This is where this Profile’s records live. Select View all.",
    number: 2,
    side: "bottom",
    align: "end"
  },
  add_documents: {
    selector: '[data-tour="add-documents"]',
    title: "Add documents",
    description: "Upload the records you want PaperBridge to organize and use for answers.",
    number: 3,
    side: "bottom",
    align: "end"
  },
  choose_files: {
    selector: '[data-tour="choose-files"]',
    title: "Choose your files",
    description: "Choose one file or several. PaperBridge will create a category and description for each document.",
    number: 4,
    side: "top",
    align: "center",
    actionLabel: "Choose files",
    fileSelector: 'input[type="file"]'
  },
  upload_submit: {
    selector: '[data-tour="upload-submit"]',
    title: "Ready to upload",
    description: "Review your selected files, then select Upload. You can remove files or clear the selection before uploading.",
    number: 4,
    side: "left",
    align: "end",
    actionLabel: "Review files",
    focusSelector: '[data-testid="document-file-list"]'
  },
  open_ask: {
    selector: '[data-tour="open-ask"]',
    fallbackSelector: '[data-tour="back-to-documents"]',
    title: "Open Ask PaperBridge",
    description: "For the best answer, wait until the records you need say Ready, then select Ask PaperBridge.",
    fallbackTitle: "Your document is uploaded",
    fallbackDescription: "PaperBridge is preparing it in the background. Go back to Documents to continue to Ask PaperBridge.",
    number: 5,
    side: "bottom",
    align: "end"
  },
  ask_question: {
    selector: '[data-tour="ask-question"]',
    title: "Ask your first question",
    description: "Choose a suggested question, or type your own and select Ask.",
    number: 6,
    side: "top",
    align: "center",
    actionLabel: "Type a question",
    focusSelector: '[data-testid="ai-assistant-query"]'
  }
}

export default class extends Controller {
  static values = {
    accountId: String,
    autoStart: Boolean,
    dashboardUrl: String
  }

  connect() {
    this.connected = true
    this.driverInstance = null
    this.suppressDismissal = false
    this.startFrame = window.requestAnimationFrame(() => this.start())
  }

  disconnect() {
    this.connected = false
    window.cancelAnimationFrame(this.startFrame)
    this.destroyTour()
  }

  beforeCache() {
    this.destroyTour()
  }

  replay() {
    if (!this.writeState(ACTIVE_STATUS, "restart")) return

    this.destroyTour()
    window.Turbo.visit(this.dashboardUrlValue)
  }

  advance(event) {
    if (!this.isPlainNavigation(event)) return

    const { fromPhase, nextPhase } = event.params
    if (!this.isActivePhase(fromPhase)) return

    this.moveTo(nextPhase)
  }

  advanceAfterSubmit(event) {
    if (!event.detail.success) return

    const { fromPhase, kind, nextPhase } = event.params
    if (!this.isActivePhase(fromPhase)) return
    if (kind === "question" && !this.validQuestion(event.currentTarget)) return

    this.moveTo(nextPhase)
  }

  filesSelected(event) {
    const hasFiles = (event.target.files?.length || 0) > 0
    const nextPhase = hasFiles ? "upload_submit" : "choose_files"
    const previousPhase = hasFiles ? "choose_files" : "upload_submit"
    if (!this.isActivePhase(previousPhase)) return

    if (!this.writeState(ACTIVE_STATUS, nextPhase)) return

    this.destroyTour()
    this.startFrame = window.requestAnimationFrame(() => this.showPhase(nextPhase))
  }

  pause(event) {
    const interactionTarget = event.target

    this.destroyTour()
    window.requestAnimationFrame(() => interactionTarget?.focus({ preventScroll: true }))
  }

  start() {
    let state = this.readState()

    if (!state) {
      if (!this.autoStartValue || !this.writeState(ACTIVE_STATUS, "create_profile")) return

      state = this.readState()
    }

    if (state?.status !== ACTIVE_STATUS) return

    const phase = this.normalizedPhase(state.phase)
    if (!phase) return

    this.showPhase(phase)
  }

  normalizedPhase(phase) {
    const profileTarget = this.visibleTarget('[data-tour="open-profile"]')
    const createTarget = this.visibleTarget('[data-tour="create-profile"]')

    if (phase === "restart") {
      const nextPhase = profileTarget ? "open_profile" : "create_profile"
      if (!profileTarget && !createTarget) return null
      if (!this.writeState(ACTIVE_STATUS, nextPhase)) return null

      return nextPhase
    }

    if (phase === "create_profile" && profileTarget) {
      if (!this.writeState(ACTIVE_STATUS, "open_profile")) return null

      return "open_profile"
    }

    if (phase === "upload_submit" && this.uploadNeedsFiles()) {
      if (!this.writeState(ACTIVE_STATUS, "choose_files")) return null

      return "choose_files"
    }

    return phase
  }

  uploadNeedsFiles() {
    const fileInput = this.visibleTarget('[data-tour="choose-files"] input[type="file"]')

    return fileInput && (fileInput.files?.length || 0) === 0
  }

  showPhase(phase) {
    if (!this.connected || !this.isActivePhase(phase)) return

    const content = STEP_CONTENT[phase]
    if (!content) return

    let target = this.visibleTarget(content.selector)
    const usingFallback = !target && content.fallbackSelector
    if (usingFallback) target = this.visibleTarget(content.fallbackSelector)
    if (!target) return

    this.destroyTour()
    document.body.classList.add("paperbridge-tour-active")

    const showButtons = content.actionLabel ? ["next", "close"] : ["close"]

    this.driverInstance = driver({
      allowClose: true,
      allowKeyboardControl: true,
      allowScroll: true,
      animate: !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
      overlayClickBehavior: () => {},
      overlayColor: "#14213d",
      overlayOpacity: 0.62,
      popoverClass: "paperbridge-tour",
      showButtons: showButtons,
      stagePadding: 8,
      stageRadius: 12,
      onDestroyed: () => this.tourDestroyed(),
      onPopoverRender: (popover) => {
        popover.wrapper.dataset.testid = "product-tour-popover"
        popover.closeButton.dataset.testid = "product-tour-close"
        popover.closeButton.setAttribute("aria-label", "Skip setup tour")
        popover.closeButton.setAttribute("title", "Skip setup tour")
        popover.nextButton.dataset.testid = "product-tour-action"
      }
    })

    this.driverInstance.highlight({
      element: target,
      popover: {
        title: `<span class="paperbridge-tour__step">Step ${content.number} of 6</span>${usingFallback ? content.fallbackTitle : content.title}`,
        description: usingFallback ? content.fallbackDescription : content.description,
        side: content.side,
        align: content.align,
        showButtons: showButtons,
        nextBtnText: content.actionLabel,
        onNextClick: content.actionLabel ? () => this.beginInteraction(target, content) : undefined
      }
    })
  }

  beginInteraction(target, content) {
    if (content.fileSelector) {
      const fileInput = target.querySelector(content.fileSelector)
      if (!fileInput) return

      this.destroyTour()
      fileInput.addEventListener("cancel", () => this.showPhase("choose_files"), { once: true })
      fileInput.click()
      return
    }

    const focusTarget = target.matches(content.focusSelector) ?
      target :
      target.querySelector(content.focusSelector) ||
        target.closest("form")?.querySelector(content.focusSelector) ||
        document.querySelector(content.focusSelector)

    this.destroyTour()
    window.requestAnimationFrame(() => focusTarget?.focus({ preventScroll: true }))
  }

  moveTo(nextPhase) {
    if (nextPhase === "completed") {
      if (!this.writeState("completed", "completed")) return
    } else if (!this.writeState(ACTIVE_STATUS, nextPhase)) {
      return
    }

    this.destroyTour()
  }

  destroyTour() {
    if (!this.driverInstance) {
      document.body.classList.remove("paperbridge-tour-active")
      return
    }

    this.suppressDismissal = true
    const activeDriver = this.driverInstance
    this.driverInstance = null
    activeDriver.destroy()
    this.suppressDismissal = false
    document.body.classList.remove("paperbridge-tour-active")
  }

  tourDestroyed() {
    this.driverInstance = null
    document.body.classList.remove("paperbridge-tour-active")

    if (this.suppressDismissal || !this.connected) return
    if (this.readState()?.status !== ACTIVE_STATUS) return

    this.writeState("dismissed", this.readState()?.phase)
  }

  isActivePhase(phase) {
    const state = this.readState()

    return state?.status === ACTIVE_STATUS && state.phase === phase
  }

  isPlainNavigation(event) {
    return !event.defaultPrevented &&
      event.button === 0 &&
      !event.metaKey &&
      !event.ctrlKey &&
      !event.shiftKey &&
      !event.altKey
  }

  validQuestion(form) {
    const question = new FormData(form).get("q")?.toString().trim() || ""

    return question.length > 0 && question.length <= 5000
  }

  visibleTarget(selector) {
    return Array.from(document.querySelectorAll(selector)).find((element) => {
      const styles = window.getComputedStyle(element)

      return styles.display !== "none" &&
        styles.visibility !== "hidden" &&
        element.getClientRects().length > 0
    })
  }

  readState() {
    try {
      const rawState = window.localStorage.getItem(this.storageKey)
      if (!rawState) return null

      const state = JSON.parse(rawState)
      if (state?.version !== TOUR_VERSION) return null
      if (![ACTIVE_STATUS, "dismissed", "completed"].includes(state.status)) return null

      return state
    } catch (_error) {
      return null
    }
  }

  writeState(status, phase) {
    try {
      window.localStorage.setItem(this.storageKey, JSON.stringify({
        version: TOUR_VERSION,
        status: status,
        phase: phase
      }))
      return true
    } catch (_error) {
      return false
    }
  }

  get storageKey() {
    return `paperbridge:getting-started:v${TOUR_VERSION}:account:${this.accountIdValue}`
  }
}
