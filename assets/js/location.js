// Resolve once on entry, then only on an explicit refresh. Never persist coordinates.
export const BrowserLocation = {
  mounted() {
    this.alive = true
    this.requesting = false
    this.requestLocation = () => {
      if (this.requesting) return
      const button = this.el.querySelector("[data-use-location]")
      if (!window.isSecureContext || !navigator.geolocation) {
        this.pushEvent("location-error", {reason: "unsupported"})
        return
      }
      this.requesting = true
      button.disabled = true
      this.el.querySelector("[data-location-progress]").textContent = "Finding your location…"
      const finish = () => {
        this.requesting = false
        button.disabled = false
        this.el.querySelector("[data-location-progress]").textContent = ""
      }
      navigator.geolocation.getCurrentPosition(position => {
        if (!this.alive) return
        const {latitude, longitude, accuracy} = position.coords
        this.pushEvent("location-detected", {latitude, longitude, accuracy}, finish)
      }, error => {
        if (!this.alive) return
        finish()
        this.pushEvent("location-error", {reason: error.code === 1 ? "denied" : error.code === 3 ? "timeout" : "unavailable"})
      }, {enableHighAccuracy: true, timeout: 15000, maximumAge: 60000})
    }
    this.el.querySelector("[data-use-location]").addEventListener("click", this.requestLocation)
    if (this.el.hasAttribute("data-auto-location")) this.requestLocation()
  },
  destroyed() {
    this.alive = false
    this.el.querySelector("[data-use-location]")?.removeEventListener("click", this.requestLocation)
  }
}
