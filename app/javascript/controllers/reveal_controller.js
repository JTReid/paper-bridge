import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static hashNavigationSettlesAt = 0
  static hashNavigationClickListener = null

  static values = {
    delay: Number,
    rootMargin: { type: String, default: "0px 0px -8% 0px" },
    threshold: { type: Number, default: 0.12 }
  }

  static ensureHashNavigationClickListener() {
    if (this.hashNavigationClickListener) return

    this.hashNavigationClickListener = (event) => {
      const link = event.target.closest("a[href]")
      if (!link) return

      const url = new URL(link.href, window.location.href)
      if (url.origin !== window.location.origin || url.pathname !== window.location.pathname || !url.hash) return

      this.markHashNavigationSettling()
    }

    document.addEventListener("click", this.hashNavigationClickListener, true)
  }

  static markHashNavigationSettling() {
    this.hashNavigationSettlesAt = performance.now() + 700
  }

  connect() {
    this.constructor.ensureHashNavigationClickListener()
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
    cancelAnimationFrame(this.hashNavigationFrame)
    this.observer?.disconnect()
    this.element.style.transitionDelay = ""
    this.element.style.transition = ""
  }

  handleIntersection(entries) {
    if (entries.some((entry) => entry.isIntersecting)) {
      if (this.isInsideHashTarget() || this.isHashNavigationSettling()) {
        this.revealImmediately()
      } else {
        this.reveal()
      }
    }
  }

  handleHashChange() {
    this.constructor.markHashNavigationSettling()

    if (this.isInsideHashTarget()) {
      this.revealImmediately()
      return
    }

    this.hashNavigationFrame = requestAnimationFrame(() => {
      if (this.isInViewport()) {
        this.revealImmediately()
      }
    })
  }

  reveal() {
    this.element.classList.add("reveal--visible")
    this.observer?.unobserve(this.element)
  }

  revealImmediately() {
    this.element.style.transition = "none"
    this.element.style.transitionDelay = "0ms"
    this.element.getBoundingClientRect()
    this.reveal()
    this.element.getBoundingClientRect()

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        this.element.style.transition = ""
      })
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

  isHashNavigationSettling() {
    return performance.now() <= this.constructor.hashNavigationSettlesAt
  }

  isInViewport() {
    const rect = this.element.getBoundingClientRect()
    return rect.top < window.innerHeight && rect.bottom > 0
  }

  get prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}
