const supportsFreshCart = version => {
  const [major,minor]=String(version || '0.0').split('.').map(Number)
  return major>0 || (major===0 && minor>=2)
}

export const BrowserCheckout = {
  mounted() {
    this.status=this.el.querySelector('[data-browser-checkout-status]')
    this.handleEvent('browser-basket',({plan})=>{
      if(plan.store!==this.el.dataset.store)return
      this.requestId=plan.request_id
      this.requiresFreshCart=plan.version>=2
      this.status.textContent='Sending basket to the extension…'
      window.postMessage({source:'shopping-agent',type:'basket:offer',plan},location.origin)
      clearTimeout(this.timer)
      this.timer=setTimeout(()=>{
        this.status.textContent='Extension not found. Download and install it below, then send the basket again.'
      },1500)
    })
    this.listener=event=>{
      if(event.source!==window || event.origin!==location.origin || event.data?.source!=='shopping-agent-extension' || event.data.request_id!==this.requestId)return
      clearTimeout(this.timer)
      if(this.requiresFreshCart && !supportsFreshCart(event.data.version)) {
        this.status.textContent='Update the checkout extension to version 0.2.0 or newer, click Reload on its chrome://extensions card, then refresh Shopping Agent and resend the order.'
        return
      }
      if(event.data.type==='basket:progress') {
        this.status.textContent=event.data.message
        return
      }
      if (event.data.error==='Invalid product link.' && !event.data.version) {
        this.status.textContent='Update the checkout extension to version 0.2.0 and click Reload on its chrome://extensions card, then resend the basket.'
        return
      }
      this.status.textContent=event.data.accepted?'Basket sent. Review it in the extension tab, sign in on the supermarket website, then click “Replace cart & build this order” in the extension.':event.data.error || 'The extension could not receive this basket.'
    }
    window.addEventListener('message',this.listener)
  },
  destroyed() {clearTimeout(this.timer);window.removeEventListener('message',this.listener)}
}
