const supportsVersion = (version, requiredMinor) => {
  const [major,minor]=String(version || '0.0').split('.').map(Number)
  return major>0 || (major===0 && minor>=requiredMinor)
}

export const BrowserCheckout = {
  mounted() {
    this.status=this.el.querySelector('[data-browser-checkout-status]')
    this.actions=Array.from(this.el.querySelectorAll('[data-checkout-action]'))
    this.sendControl=action=>window.postMessage({source:'shopping-agent',type:'basket:control',request_id:this.requestId,action},location.origin)
    this.actionListener=event=>{
      const button=event.target.closest('[data-checkout-action]')
      if(button && this.el.contains(button))this.sendControl(button.dataset.checkoutAction)
    }
    this.el.addEventListener('click',this.actionListener)
    this.showProgress=({status,message})=>{
      this.status.textContent=message
      this.el.dataset.checkoutState=status || ''
      if(['stopped','closed'].includes(status) && typeof document!=='undefined' && document.getElementById('browser-cart-notification')?.dataset.requestId===this.requestId)document.getElementById('browser-cart-notification').remove()
      for(const button of this.actions) {
        const action=button.dataset.checkoutAction
        button.hidden=action==='setup'?status!=='permission_required':action==='focus'?!['ready','attention'].includes(status):action==='resume'?status!=='attention':!['starting','opening','loading','executing','probing','attention','permission_required'].includes(status)
        if(action==='focus')button.textContent=status==='ready'?'Open cart & checkout':'Open supermarket'
      }
      if(status==='ready' && this.notifiedRequest!==this.requestId && typeof document!=='undefined') {
        this.notifiedRequest=this.requestId
        document.getElementById('browser-cart-notification')?.remove()
        const notice=document.createElement('div')
        notice.id='browser-cart-notification';notice.className='browser-cart-notification';notice.setAttribute('role','status');notice.dataset.requestId=this.requestId
        const text=document.createElement('span');text.textContent='Your supermarket cart is ready. Review it and complete checkout.'
        const open=document.createElement('button');open.type='button';open.textContent='Open cart';open.addEventListener('click',()=>this.sendControl('focus'))
        const close=document.createElement('button');close.type='button';close.textContent='Dismiss';close.addEventListener('click',()=>notice.remove())
        notice.append(text,open,close);document.body.append(notice)
      }
    }
    this.handleEvent('browser-basket',({plan})=>{
      if(plan.store!==this.el.dataset.store)return
      this.requestId=plan.request_id
      this.requiredMinor=plan.version>=3?3:plan.version>=2?2:0
      if(typeof document!=='undefined')document.getElementById('browser-cart-notification')?.remove()
      this.showProgress({status:'starting',message:'Preparing your fresh cart in the background…'})
      window.postMessage({source:'shopping-agent',type:'basket:offer',plan},location.origin)
      clearTimeout(this.timer)
      this.timer=setTimeout(()=>{
        this.showProgress({status:'missing',message:'Extension not found. Download and install it below, then prepare the cart again.'})
      },5000)
    })
    this.listener=event=>{
      if(event.source!==window || event.origin!==location.origin || event.data?.source!=='shopping-agent-extension' || event.data.request_id!==this.requestId)return
      clearTimeout(this.timer)
      if(this.requiredMinor && !supportsVersion(event.data.version,this.requiredMinor)) {
        this.showProgress({status:'outdated',message:`Update the checkout extension to version 0.${this.requiredMinor}.0 or newer, click Reload on its chrome://extensions card, then refresh Shopping Agent and prepare the cart again.`})
        return
      }
      if(event.data.type==='basket:progress') {this.showProgress(event.data);return}
      if(event.data.control) {
        if(event.data.error)this.status.textContent=event.data.error
        return
      }
      if(event.data.accepted) {
        this.showProgress({status:event.data.status || 'starting',message:event.data.message || 'Preparing your fresh cart in the background. We’ll notify you here when it is ready.'})
      } else this.showProgress({status:'error',message:event.data.error || 'The extension could not receive this basket.'})
    }
    window.addEventListener('message',this.listener)
  },
  destroyed() {
    clearTimeout(this.timer);window.removeEventListener('message',this.listener);this.el.removeEventListener('click',this.actionListener)
    if(typeof document!=='undefined' && document.getElementById('browser-cart-notification')?.dataset.requestId===this.requestId)document.getElementById('browser-cart-notification').remove()
  }
}
