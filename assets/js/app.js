// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/oculpado"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const Hooks = {}

// Anima o número quando a contagem muda (efeito "bump")
Hooks.Bump = {
  updated() {
    const now = this.el.dataset.count
    if (this._last !== undefined && this._last !== now) {
      this.el.classList.remove("bump")
      void this.el.offsetWidth // reinicia a animação
      this.el.classList.add("bump")
    }
    this._last = now
  },
  mounted() {
    this._last = this.el.dataset.count
  },
}

// Anima a reordenação da lista (técnica FLIP)
Hooks.FlipList = {
  positions() {
    const map = new Map()
    for (const child of this.el.children) {
      map.set(child.id, child.getBoundingClientRect().top)
    }
    return map
  },
  mounted() {
    this._pos = this.positions()
  },
  beforeUpdate() {
    this._pos = this.positions()
  },
  updated() {
    const oldPos = this._pos || new Map()
    for (const child of this.el.children) {
      const prev = oldPos.get(child.id)
      if (prev === undefined) continue
      const delta = prev - child.getBoundingClientRect().top
      if (delta) {
        child.animate(
          [{transform: `translateY(${delta}px)`}, {transform: "translateY(0)"}],
          {duration: 420, easing: "cubic-bezier(0.22, 1, 0.36, 1)"}
        )
      }
    }
    this._pos = this.positions()
  },
}

// Persiste a seleção do usuário no navegador (uma chave por partida)
Hooks.VoterSync = {
  mounted() {
    const key = this.el.dataset.storeKey || "oculpado:selected"
    const raw = localStorage.getItem(key)
    if (raw) {
      try {
        const ids = JSON.parse(raw)
        if (Array.isArray(ids) && ids.length) this.pushEvent("restore", {ids})
      } catch (_e) {}
    }
    this.handleEvent("sync_selected", ({key: k, ids}) => {
      localStorage.setItem(k || key, JSON.stringify(ids))
    })
  },
}

// Contagem regressiva até o horário do jogo (data-kickoff em ISO8601).
// Roda no cliente (relógio do torcedor), sem round-trip ao servidor a cada segundo.
Hooks.Countdown = {
  mounted() {
    this.target = new Date(this.el.dataset.kickoff).getTime()
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  },
  destroyed() {
    clearInterval(this.timer)
  },
  tick() {
    if (isNaN(this.target)) {
      this.el.textContent = ""
      return
    }
    const diff = this.target - Date.now()
    if (diff <= 0) {
      this.el.textContent = "🔴 bola rolando"
      this.el.classList.add("is-live")
      clearInterval(this.timer)
      return
    }
    const pad = n => String(n).padStart(2, "0")
    const total = Math.floor(diff / 1000)
    const d = Math.floor(total / 86400)
    const h = Math.floor((total % 86400) / 3600)
    const m = Math.floor((total % 3600) / 60)
    const s = total % 60
    const clock = d > 0
      ? `${d}d ${pad(h)}h ${pad(m)}m ${pad(s)}s`
      : `${pad(h)}h ${pad(m)}m ${pad(s)}s`
    this.el.textContent = `⏱ faltam ${clock}`
  },
}

// Compartilhamento: usa a Web Share API nativa; se não houver, copia o link
Hooks.Share = {
  mounted() {
    this.el.addEventListener("click", async () => {
      const url = this.el.dataset.url
      const text = this.el.dataset.text
      const label = this.el.querySelector(".btn-label")
      if (navigator.share) {
        try {
          await navigator.share({title: "O Culpado", text, url})
        } catch (_e) {}
      } else {
        try {
          await navigator.clipboard.writeText(url)
          if (label) {
            const prev = label.textContent
            label.textContent = "Link copiado!"
            setTimeout(() => (label.textContent = prev), 1800)
          }
        } catch (_e) {}
      }
    })
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

