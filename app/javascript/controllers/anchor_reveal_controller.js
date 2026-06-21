import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.handleClick = this.handleClick.bind(this)
    this.element.addEventListener("click", this.handleClick)
  }

  disconnect() {
    this.element.removeEventListener("click", this.handleClick)
  }

  handleClick(event) {
    const link = event.target.closest("a[href]")
    if (!link || !this.element.contains(link)) return

    const url = new URL(link.href, window.location.href)
    if (url.origin !== window.location.origin || url.pathname !== window.location.pathname || !url.hash) return
    if (!this.hasTargetElement(url.hash)) return

    this.revealPendingContent()
  }

  hasTargetElement(hash) {
    try {
      return Boolean(document.querySelector(hash))
    } catch {
      return false
    }
  }

  revealPendingContent() {
    this.element.querySelectorAll(".reveal--pending:not(.reveal--visible)").forEach((element) => {
      element.style.transition = "none"
      element.classList.add("reveal--visible")

      requestAnimationFrame(() => {
        element.style.transition = ""
      })
    })
  }
}
