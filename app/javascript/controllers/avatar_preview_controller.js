import { Controller } from "@hotwired/stimulus"

// Shows a newly picked profile photo in place of the current one before the
// form is saved. The server still validates the upload on save.
export default class extends Controller {
  static targets = ["input", "current", "image"]

  connect() {
    // Turbo can restore a cached copy of this page with an old preview showing.
    this.showCurrent()
  }

  disconnect() {
    this.releaseImage()
  }

  show() {
    const file = this.inputTarget.files[0]
    const acceptedTypes = this.inputTarget.accept.split(",")

    if (!file || !acceptedTypes.includes(file.type)) {
      this.showCurrent()
      return
    }

    this.releaseImage()
    this.objectURL = URL.createObjectURL(file)
    this.imageTarget.src = this.objectURL
    this.imageTarget.hidden = false
    this.currentTarget.hidden = true
  }

  showCurrent() {
    this.releaseImage()
    this.imageTarget.hidden = true
    this.imageTarget.removeAttribute("src")
    this.currentTarget.hidden = false
  }

  releaseImage() {
    if (this.objectURL) URL.revokeObjectURL(this.objectURL)
    this.objectURL = null
  }
}
