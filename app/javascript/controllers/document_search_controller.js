import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  clear(event) {
    if (event.target.value !== "") return

    event.target.disabled = true
    this.element.requestSubmit()
  }
}
