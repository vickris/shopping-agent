export const RemoteCheckout = {
  mounted() {
    this.screen = this.el.querySelector('[data-remote-screen]')
    this.input = this.el.querySelector('[data-remote-input]')
    this.status = this.el.querySelector('[data-remote-status]')
    this.tabs = this.el.querySelector('[data-remote-tabs]')
    this.queue = []
    this.running = false
    this.stopped = false
    this.dead = false
    this.lastInput = Date.now()
    this.previousFocus = document.activeElement
    this.controller = new AbortController()
    const on = (el, name, callback, options = {}) => el.addEventListener(name, callback, {...options, signal: this.controller.signal})
    const enqueue = action => {
      if (this.stopped || this.dead) return
      this.lastInput = Date.now()
      // Batch typing while a frame is in flight; never replay an uncertain input.
      const last = this.queue.at(-1)
      if (action.type === 'text' && last?.type === 'text' && (last.text + action.text).length <= 2048) last.text += action.text
      else if (this.queue.length < 128) this.queue.push(action)
      else { this.fail('Too much input queued. Close this view and reopen it to check the store state.'); return }
      this.pump()
    }
    on(this.screen, 'click', event => {
      const rect = this.screen.getBoundingClientRect()
      enqueue({type: 'click', x: Math.min(1023, Math.max(0, (event.clientX - rect.left) * 1024 / rect.width)), y: Math.min(767, Math.max(0, (event.clientY - rect.top) * 768 / rect.height))})
      this.input.focus({preventScroll: true})
    })
    on(this.screen, 'wheel', event => {
      event.preventDefault()
      if (Date.now() - (this.lastWheel || 0) < 100) return
      this.lastWheel = Date.now()
      enqueue({type: 'scroll', delta: Math.max(-768, Math.min(768, event.deltaY))})
    }, {passive: false})
    const flushText = () => {
      const value = this.input.value
      this.input.value = ''
      if (value) enqueue({type: 'text', text: value.slice(0, 2048)})
    }
    on(this.input, 'beforeinput', event => {
      if (event.inputType === 'deleteContentBackward' || event.inputType === 'deleteContentForward') {
        event.preventDefault()
        enqueue({type: 'key', key: event.inputType === 'deleteContentBackward' ? 'Backspace' : 'Delete'})
      }
    })
    on(this.input, 'input', event => { if (!event.isComposing) flushText() })
    on(this.input, 'compositionend', () => queueMicrotask(flushText))
    on(this.input, 'keydown', event => {
      if (event.isComposing) return
      let key = event.key
      if ((event.ctrlKey || event.metaKey) && key.toLowerCase() === 'a') key = 'ControlOrMeta+A'
      else if (key === 'Tab' && event.shiftKey) key = 'Shift+Tab'
      if (['Enter', 'Tab', 'Shift+Tab', 'Backspace', 'Delete', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End', 'Escape', 'ControlOrMeta+A'].includes(key)) {
        event.preventDefault()
        enqueue({type: 'key', key})
      }
    })
    on(this.tabs, 'change', () => enqueue({type: 'tab', index: Number(this.tabs.value)}))
    this.el.querySelectorAll('[data-remote-key]').forEach(el => on(el, 'click', () => enqueue({type: 'key', key: el.dataset.remoteKey})))
    this.el.querySelectorAll('[data-remote-scroll]').forEach(el => on(el, 'click', () => enqueue({type: 'scroll', delta: Number(el.dataset.remoteScroll)})))
    this.el.querySelectorAll('button[data-remote-dialog]').forEach(el => on(el, 'click', () => {
      const prompt = this.el.querySelector('[data-remote-prompt]')
      const action = {type: 'dialog', choice: el.dataset.remoteDialog}
      if (prompt && !prompt.hidden) { action.text = prompt.value.slice(0, 2048); prompt.value = '' }
      enqueue(action)
    }))
    this.timer = setInterval(() => {
      if (!document.hidden && Date.now() - this.lastInput < 300_000) this.pump()
      else if (!this.running) this.status.textContent = 'View paused while inactive. Tap a control to resume. The private session still expires automatically.'
    }, 1000)
    this.input.focus({preventScroll: true})
    this.pump()
  },
  pump() {
    if (this.running || this.stopped || this.dead) return
    this.running = true
    const action = this.queue.shift() || {type: 'frame'}
    this.timeout = setTimeout(() => this.fail('Connection interrupted. Reopen checkout to inspect the store before repeating any payment action.'), 12_000)
    this.pushEvent('remote-control', {remote_input: action}, reply => {
      clearTimeout(this.timeout)
      if (this.dead || this.stopped) return
      this.running = false
      if (reply.error || !reply.remote_frame) { this.fail(reply.error || 'Private checkout is unavailable.'); return }
      const frame = reply.remote_frame
      this.screen.src = `data:image/jpeg;base64,${frame.image}`
      this.screen.width = frame.width
      this.screen.height = frame.height
      const signature = JSON.stringify(frame.tabs)
      if (signature !== this.tabSignature) {
        this.tabs.replaceChildren(...frame.tabs.map(tab => {
          const option = document.createElement('option')
          option.value = String(tab.index)
          option.textContent = tab.host || 'New tab'
          return option
        }))
        this.tabSignature = signature
      }
      this.tabs.value = String(frame.active)
      this.el.querySelector('div[data-remote-dialog]').hidden = !frame.dialog
      const dialogMessage = this.el.querySelector('[data-remote-dialog-message]')
      if (dialogMessage) dialogMessage.textContent = frame.dialog?.message || ''
      const prompt = this.el.querySelector('[data-remote-prompt]')
      if (prompt) { prompt.hidden = frame.dialog?.type !== 'prompt'; if (prompt.hidden) prompt.value = '' }
      const host = frame.tabs.find(tab => tab.index === frame.active)?.host
      this.status.textContent = host ? `Connected to ${host} · Only you control this session` : 'Waiting for the store page'
      if (this.queue.length) this.pump()
    })
  },
  fail(message) {
    this.stopped = true
    this.queue = []
    this.input.value = ''
    const prompt = this.el.querySelector('[data-remote-prompt]')
    if (prompt) prompt.value = ''
    this.screen.removeAttribute('src')
    this.status.textContent = message
    clearInterval(this.timer)
    clearTimeout(this.timeout)
  },
  disconnected() {
    this.fail('Connection interrupted. Reopen checkout to inspect the store before repeating any payment action.')
  },
  destroyed() {
    this.dead = true
    this.stopped = true
    this.queue = []
    this.input.value = ''
    const prompt = this.el.querySelector('[data-remote-prompt]')
    if (prompt) prompt.value = ''
    this.screen.removeAttribute('src')
    clearInterval(this.timer)
    clearTimeout(this.timeout)
    this.controller.abort()
    if (this.previousFocus?.isConnected) this.previousFocus.focus({preventScroll: true})
  }
}
