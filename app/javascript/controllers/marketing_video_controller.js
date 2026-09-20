import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "video", "trigger", "closeButton", "error"]

  open(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

    event.preventDefault()
    this.errorTarget.hidden = true
    this.dialogTarget.showModal()
    this.triggerTarget.setAttribute("aria-expanded", "true")
    document.body.classList.add("overflow-hidden")
    this.closeButtonTarget.focus()

    this.videoTarget.src = this.triggerTarget.href
    this.videoTarget.play().catch(() => {
      // Playback policies may require another click on the native controls.
      // Loading failures are handled by the video's error event.
    })
  }

  close() {
    this.dialogTarget.close()
  }

  closeOnBackdrop(event) {
    if (event.target !== this.dialogTarget) return

    const bounds = this.dialogTarget.getBoundingClientRect()
    const outsideDialog = event.clientX < bounds.left || event.clientX > bounds.right ||
      event.clientY < bounds.top || event.clientY > bounds.bottom

    if (outsideDialog) this.close()
  }

  showError() {
    if (this.dialogTarget.open && this.videoTarget.error) this.errorTarget.hidden = false
  }

  restorePage() {
    this.reset()
    if (this.triggerTarget.isConnected) this.triggerTarget.focus({ preventScroll: true })
  }

  reset() {
    if (this.videoTarget.hasAttribute("src")) {
      this.videoTarget.pause()
      this.videoTarget.removeAttribute("src")
      this.videoTarget.load()
    }
    this.errorTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    document.body.classList.remove("overflow-hidden")
  }

  beforeCache() {
    this.close()
    this.reset()
  }

  disconnect() {
    this.beforeCache()
  }
}
