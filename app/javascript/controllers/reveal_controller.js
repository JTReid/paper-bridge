import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    delay: Number,
    rootMargin: { type: String, default: "0px 0px -8% 0px" },
    threshold: { type: Number, default: 0.12 }
  }

  connect() {
    this.element.classList.add("reveal--pending")
    this.element.style.transitionDelay = `${this.delayValue || 0}ms`

    if (this.prefersReducedMotion || !("IntersectionObserver" in window)) {
      this.reveal()
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
    this.observer?.disconnect()
    this.element.style.transitionDelay = ""
  }

  handleIntersection(entries) {
    if (entries.some((entry) => entry.isIntersecting)) {
      this.reveal()
    }
  }

  reveal() {
    this.element.classList.add("reveal--visible")
    this.observer?.unobserve(this.element)
  }

  get prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}
