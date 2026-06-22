import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    delay: Number,
    rootMargin: { type: String, default: "0px 0px -8% 0px" },
    threshold: { type: Number, default: 0.12 }
  }

  connect() {
    this.handleHashChange = this.handleHashChange.bind(this)
    this.element.classList.add("reveal--pending")
    this.element.style.transitionDelay = `${this.delayValue || 0}ms`

    if (this.prefersReducedMotion || !("IntersectionObserver" in window)) {
      this.reveal()
      return
    }

    window.addEventListener("hashchange", this.handleHashChange)

    if (this.isInsideHashTarget()) {
      this.revealImmediately()
      return
    }

    this.observer = new IntersectionObserver(
      (entries) => this.handleIntersection(entries),
      {
        rootMargin: this.rootMarginValue,
        threshold: this.thresholdValue
      }
    )
    this.observer.observe(this.element)
  }

  disconnect() {
    window.removeEventListener("hashchange", this.handleHashChange)
    this.observer?.disconnect()
    this.element.style.transitionDelay = ""
    this.element.style.transition = ""
  }

  handleIntersection(entries) {
    if (entries.some((entry) => entry.isIntersecting)) {
      if (this.isInsideHashTarget()) {
        this.revealImmediately()
      } else {
        this.reveal()
      }
    }
  }

  handleHashChange() {
    if (this.isInsideHashTarget()) {
      this.revealImmediately()
    }
  }

  reveal() {
    this.element.classList.add("reveal--visible")
    this.observer?.unobserve(this.element)
  }

  revealImmediately() {
    this.element.style.transition = "none"
    this.element.style.transitionDelay = "0ms"
    this.reveal()

    requestAnimationFrame(() => {
      this.element.style.transition = ""
    })
  }

  isInsideHashTarget() {
    if (!window.location.hash) return false

    try {
      const target = document.querySelector(window.location.hash)
      return Boolean(target?.contains(this.element))
    } catch {
      return false
    }
  }

  get prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}
