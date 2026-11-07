// Smoke test for website/: screenshots at desktop and phone width, checks for
// horizontal scroll, console errors, broken images and the lightbox.
// Usage:
//   (cd website && python3 -m http.server 8765) &
//   node tools/website_check.js [baseUrl] [outDir]
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const base = process.argv[2] || 'http://localhost:8765';
const out = process.argv[3] || path.join(__dirname, '..', 'screenshots', 'website');
fs.mkdirSync(out, { recursive: true });

const pages = ['index.html', 'presskit.html', 'privacy.html'];
const viewports = [
  { name: 'desktop', width: 1440, height: 900 },
  { name: 'phone', width: 390, height: 844, isMobile: true, hasTouch: true, deviceScaleFactor: 2 },
];

(async () => {
  const browser = await chromium.launch();
  let failures = 0;
  const fail = (m) => { failures++; console.log('FAIL ' + m); };
  for (const vp of viewports) {
    const ctx = await browser.newContext({
      viewport: { width: vp.width, height: vp.height },
      isMobile: !!vp.isMobile, hasTouch: !!vp.hasTouch, deviceScaleFactor: vp.deviceScaleFactor || 1,
    });
    for (const p of pages) {
      const page = await ctx.newPage();
      const errors = [];
      page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
      page.on('pageerror', (e) => errors.push(String(e)));
      page.on('requestfailed', (r) => errors.push('request failed: ' + r.url()));
      page.on('response', (r) => { if (r.status() >= 400) errors.push(r.status() + ' ' + r.url()); });
      await page.goto(`${base}/${p}`, { waitUntil: 'networkidle' });
      // Scroll through so lazy images load and reveals trigger.
      await page.evaluate(async () => {
        for (let y = 0; y < document.body.scrollHeight; y += 500) { window.scrollTo({ top: y, behavior: 'instant' }); await new Promise((r) => setTimeout(r, 80)); }
        window.scrollTo({ top: 0, behavior: 'instant' });
      });
      await page.waitForTimeout(900);
      const m = await page.evaluate(() => ({
        sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth,
        wide: [...document.querySelectorAll('body *')].filter((el) => el.getBoundingClientRect().right > document.documentElement.clientWidth + 1 && getComputedStyle(el).position !== 'fixed' && !el.closest('.hp,.visually-hidden,dialog')).slice(0, 5).map((el) => el.tagName + '.' + el.className),
        broken: [...document.images].filter((i) => i.complete && i.naturalWidth === 0 && i.getAttribute('src')).map((i) => i.src),
        noAlt: [...document.images].filter((i) => !i.hasAttribute('alt')).length,
      }));
      const tag = `${vp.name} ${p}`;
      if (m.sw > m.cw) fail(`${tag}: horizontal scroll ${m.sw} > ${m.cw} ${JSON.stringify(m.wide)}`);
      if (m.broken.length) fail(`${tag}: broken images ${m.broken.join(', ')}`);
      if (m.noAlt) fail(`${tag}: ${m.noAlt} images without alt`);
      if (errors.length) fail(`${tag}: console/network errors\n  ${errors.join('\n  ')}`);

      if (p === 'index.html') {
        await page.screenshot({ path: path.join(out, `${vp.name}_full.png`), fullPage: true });
        await page.screenshot({ path: path.join(out, `${vp.name}_hero.png`) });
        // Lightbox: open, next, keyboard, close.
        const first = page.locator('#gallery a[data-lightbox]').first();
        await first.scrollIntoViewIfNeeded();
        await first.click();
        await page.waitForTimeout(500);
        const open1 = await page.evaluate(() => ({ open: document.getElementById('lightbox').open, src: document.querySelector('#lightbox img').src, n: document.querySelector('#lightbox .count').textContent }));
        if (!open1.open || !open1.src.includes('.webp')) fail(`${tag}: lightbox did not open`);
        await page.keyboard.press('ArrowRight');
        await page.waitForTimeout(400);
        const n2 = await page.evaluate(() => document.querySelector('#lightbox .count').textContent);
        if (n2 === open1.n) fail(`${tag}: lightbox ArrowRight did not advance (${n2})`);
        const ok = await page.evaluate(() => { const i = document.querySelector('#lightbox img'); return i.complete && i.naturalWidth > 0; });
        if (!ok) fail(`${tag}: lightbox image did not load`);
        await page.screenshot({ path: path.join(out, `${vp.name}_lightbox.png`) });
        await page.keyboard.press('Escape');
        await page.waitForTimeout(300);
        if (await page.evaluate(() => document.getElementById('lightbox').open)) fail(`${tag}: Escape did not close lightbox`);
        // Newsletter without an endpoint shows the "opens soon" message.
        await page.fill('#nl-email', 'test@example.com');
        await page.click('#signup-form button[type=submit]');
        const msg = await page.textContent('#newsletter .form-msg');
        if (!msg.trim()) fail(`${tag}: newsletter gave no message`);
        console.log(`ok   ${tag}: lightbox ${open1.n} -> ${n2}, newsletter "${msg.trim()}"`);
      } else {
        await page.screenshot({ path: path.join(out, `${vp.name}_${p.replace('.html', '')}.png`), fullPage: true });
        console.log(`ok   ${tag}`);
      }
      await page.close();
    }
    await ctx.close();
  }
  await browser.close();
  console.log(failures ? `${failures} problem(s)` : 'all checks passed');
  process.exit(failures ? 1 : 0);
})();
