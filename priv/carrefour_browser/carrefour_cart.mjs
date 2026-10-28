// Runs in the page against the visible cart, including Carrefour's newer widget.
// Keep self-contained: Playwright serializes this function into the browser.
export function cartMatches(expected) {
  const visible = el => Boolean(el.getClientRects().length);
  const widgets = Array.from(document.querySelectorAll('main [data-testid="expanded-widget"]'))
    .filter(el => visible(el) && !el.closest('.group'));
  let rows;
  if (widgets.length) {
    rows = widgets.map(widget => {
      let row = widget.parentElement;
      while (row && row.tagName !== 'MAIN' && !(row.querySelector('a[href*="/p/"]') && row.querySelector('.items-baseline'))) row = row.parentElement;
      if (!row || row.tagName === 'MAIN') return null;
      const counter = widget.cloneNode(true);
      counter.querySelectorAll('button').forEach(el => el.remove());
      const quantity = counter.textContent.trim();
      const price = row.querySelector('.items-baseline').cloneNode(true);
      price.querySelectorAll('del,s,.line-through').forEach(el => el.remove());
      const match = price.textContent.replaceAll(',', '').match(/^\s*KES\s*(\d+)(?:\.(\d{1,2}))?\s*$/);
      return {
        id: new URL(row.querySelector('a[href*="/p/"]').href).pathname.match(/\/p\/([^/]+)$/)?.[1],
        quantity: /^\d+$/.test(quantity) ? Number(quantity) : NaN,
        total: match ? (BigInt(match[1]) * 100n + BigInt((match[2] || '').padEnd(2, '0'))).toString() : null
      };
    });
  } else {
    // Older storefront layouts expose a combobox instead of an expanded widget.
    rows = Array.from(document.querySelectorAll('[id^="entries-"] div.relative.rounded-xl'))
      .filter(row => row.querySelector('[role="combobox"]') && visible(row))
      .map(row => ({id: row.querySelector('a[href*="/p/"]')?.href.match(/\/p\/([^/?#]+)/)?.[1], quantity: Number(row.querySelector('[role="combobox"]').textContent.trim())}));
  }
  return rows.length === expected.length && expected.every(p => {
    const matching = rows.filter(row => row?.id === p.id);
    return matching.length === 1 && matching[0].quantity === p.packs &&
      (!Object.hasOwn(matching[0], 'total') || matching[0].total === p.total);
  });
}

export async function verifyCarrefourCart(page, products, cents, timeout = 20000) {
  const expected = products.map(p => ({id: p.id, packs: p.packs, total: (cents(p.expected_price) * BigInt(p.packs)).toString()}));
  try {
    await page.waitForFunction(cartMatches, expected, {timeout});
  } catch (error) {
    if (error.name === 'TimeoutError') throw Error('cart_mismatch');
    throw error;
  }
}
