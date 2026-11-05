export const BrowserCheckout = {
  mounted() {
    this.status=this.el.querySelector('[data-browser-checkout-status]')
    this.handleEvent('browser-basket',({plan})=>{
      if(plan.store!==this.el.dataset.store)return
      this.requestId=plan.request_id
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
      this.status.textContent=event.data.accepted?'Basket sent. Review it in the extension tab, sign in on the supermarket website, then build your basket there.':event.data.error || 'The extension could not receive this basket.'
    }
    window.addEventListener('message',this.listener)
  },
  destroyed() {clearTimeout(this.timer);window.removeEventListener('message',this.listener)}
}
