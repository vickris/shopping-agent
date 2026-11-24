// Carrefour mounts product images only after their cards enter the viewport.
// Bound the extra wait so missing optional images never fail a valid search.
export async function loadCarrefourImages(page, {timeout=8000}={}) {
  const deadline=Date.now()+timeout;
  const cards=page.locator('div.group').filter({has:page.locator(':scope > a[href*="/p/"] span.line-clamp-2')});
  const count=await cards.count();
  for(let i=0;i<count && Date.now()<deadline;i++) {
    const card=cards.nth(i);
    if(await card.locator('img[alt^="Product image"][src]').count())continue;
    try {
      await card.scrollIntoViewIfNeeded({timeout:Math.max(1,deadline-Date.now())});
      await card.locator('img[alt^="Product image"][src]').first().waitFor({
        state:'attached',timeout:Math.max(1,Math.min(i===0?3000:500,deadline-Date.now()))
      });
    } catch { /* Keep the product and its existing no-image fallback. */ }
  }
}
