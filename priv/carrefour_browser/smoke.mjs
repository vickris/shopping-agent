// Packaging smoke test: no supermarket traffic, credentials or customer state.
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '0';
const {chromium, firefox} = await import('playwright');
for (const [name, engine] of [['chromium', chromium], ['firefox', firefox]]) {
  const browser = await engine.launch({headless: true, ...(name === 'chromium' ? {channel: 'chromium'} : {})});
  try {
    const page = await browser.newPage();
    await page.setContent('<title>Browser runtime ready</title>');
    if (await page.title() !== 'Browser runtime ready') throw Error(`${name} smoke test failed`);
    process.stdout.write(`${name}: ready\n`);
  } finally {
    await browser.close();
  }
}
