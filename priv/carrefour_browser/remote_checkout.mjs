// Frames and input stay in the owning LiveView connection. No recordings,
// filesystem writes, browser debugging ports, or transferable session URLs.
export function remoteCheckout(getPage) {
  let current, pendingDialog, lastImage, attachedContext;
  const attached = new WeakSet();
  const activePage = () => {
    const original = getPage();
    const pages = original.context().pages().filter(p => !p.isClosed());
    const attach = page => {
      if (!attached.has(page)) {
        attached.add(page);
        page.on('dialog', dialog => { pendingDialog = dialog; });
      }
    };
    if (!attachedContext) {
      attachedContext = original.context();
      attachedContext.on('page', attach);
    }
    for (const page of pages) attach(page);
    if (!current || current.isClosed()) current = pages.at(-1) || original;
    return {page: current, pages};
  };
  const number = (value, max) => typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= max;
  const keys = new Set(['Enter', 'Tab', 'Shift+Tab', 'Backspace', 'Delete', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End', 'Escape', 'ControlOrMeta+A', 'Space']);
  return async input => {
    let {page, pages} = activePage();
    switch (input.type) {
      case 'frame': break;
      case 'click':
        if (!number(input.x, 1024) || !number(input.y, 768)) throw Error('invalid_input');
        await page.mouse.click(input.x, input.y); break;
      case 'scroll':
        if (typeof input.delta !== 'number' || !Number.isFinite(input.delta) || Math.abs(input.delta) > 768) throw Error('invalid_input');
        await page.mouse.wheel(0, input.delta); break;
      case 'text':
        if (typeof input.text !== 'string' || input.text.length > 2048) throw Error('invalid_input');
        await page.keyboard.insertText(input.text); break;
      case 'key':
        if (!keys.has(input.key)) throw Error('invalid_input');
        await page.keyboard.press(input.key); break;
      case 'tab':
        if (!Number.isInteger(input.index) || !pages[input.index]) throw Error('invalid_input');
        current = page = pages[input.index]; break;
      case 'dialog':
        if (!pendingDialog || !['accept', 'dismiss'].includes(input.choice)) throw Error('invalid_input');
        if (input.text != null && (typeof input.text !== 'string' || input.text.length > 2048)) throw Error('invalid_input');
        if (input.choice === 'accept') await pendingDialog.accept(input.text || ''); else await pendingDialog.dismiss();
        pendingDialog = null; break;
      default: throw Error('invalid_input');
    }
    // Fixed dimensions give deterministic click coordinates on desktop and phone.
    if (page.viewportSize()?.width !== 1024 || page.viewportSize()?.height !== 768) await page.setViewportSize({width: 1024, height: 768});
    const image = pendingDialog && lastImage ? lastImage : await page.screenshot({type: 'jpeg', quality: 65, timeout: 5000});
    lastImage = image;
    if (image.length > 1_500_000) throw Error('frame_too_large');
    const host = p => { try { return new URL(p.url()).hostname; } catch { return ''; } };
    return {image: image.toString('base64'), width: 1024, height: 768,
      tabs: pages.map((p, index) => ({index, host: host(p)})),
      active: pages.indexOf(page), dialog: pendingDialog ? {type: pendingDialog.type(), message: pendingDialog.message().slice(0, 4096)} : null};
  };
}
