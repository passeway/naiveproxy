// Browser checks for the public static page; run with Playwright and Chrome.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require('playwright');

async function main() {
  const html = await fs.readFile(path.join(__dirname, '..', 'index.html'));
  const output = process.env.SITE_SCREENSHOTS || path.join(process.cwd(), 'site-screenshots');
  await fs.mkdir(output, { recursive: true });
  const server = http.createServer((request, response) => {
    if (request.url !== '/') { response.writeHead(404); response.end(); return; }
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    response.end(html);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({ channel: process.env.BROWSER_CHANNEL || 'chrome' });
    const origin = `http://127.0.0.1:${server.address().port}`;
    for (const width of [320, 375, 768, 1024, 1440]) {
      const context = await browser.newContext({ viewport: { width, height: 900 }, reducedMotion: 'reduce' });
      const page = await context.newPage();
      const errors = [], external = [];
      page.on('pageerror', error => errors.push(error.message));
      page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
      page.on('request', request => { if (!request.url().startsWith(origin + '/')) external.push(request.url()); });
      await page.goto(origin, { waitUntil: 'networkidle' });
      await page.evaluate(() => document.fonts.ready);
      assert.equal(await page.locator('h1').count(), 1);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `${width}: horizontal overflow`);
      const broken = await page.locator('a[href^="#"]').evaluateAll(links => links
        .filter(link => !document.getElementById(link.hash.slice(1))).map(link => link.hash));
      assert.deepEqual(broken, [], `${width}: broken navigation`);
      for (const link of await page.locator('nav a').all()) {
        assert.equal(await link.isVisible(), true, `${width}: hidden navigation`);
        await link.click();
        assert.equal(new URL(page.url()).hash, await link.getAttribute('href'));
      }
      await page.goto(origin, { waitUntil: 'networkidle' });
      await page.screenshot({ path: path.join(output, `${width}.png`), fullPage: true });
      await page.keyboard.press('Tab');
      assert.equal(await page.locator('.skip-link').evaluate(element => element === document.activeElement), true);
      assert.notEqual(await page.locator('.skip-link').evaluate(element => getComputedStyle(element).outlineStyle), 'none');
      await page.keyboard.press('Enter');
      assert.equal(await page.evaluate(() => document.activeElement.id), 'main');
      assert.equal(await page.evaluate(() => getComputedStyle(document.documentElement).scrollBehavior), 'auto');
      const question = page.locator('.faq-list details').first();
      await question.locator('summary').focus();
      await page.keyboard.press('Enter');
      assert.notEqual(await question.getAttribute('open'), null, `${width}: FAQ keyboard expansion`);
      assert.equal(await question.locator('p').isVisible(), true);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `${width}: expanded FAQ overflow`);
      await page.keyboard.press('Space');
      assert.equal(await question.getAttribute('open'), null, `${width}: FAQ keyboard collapse`);
      assert.deepEqual(external, [], `${width}: external requests`);
      assert.deepEqual(errors, [], `${width}: browser errors`);
      console.log(`${width}px: layout, navigation, FAQ keyboard controls, reduced motion and offline assets OK`);
      await context.close();
    }
    const context = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 375, height: 812 } });
    const page = await context.newPage();
    await page.goto(origin);
    assert.equal(await page.locator('main').isVisible(), true);
    await page.locator('nav a[href="#capabilities"]').click();
    assert.equal(new URL(page.url()).hash, '#capabilities');
    const question = page.locator('.faq-list details').first();
    await question.locator('summary').click();
    assert.notEqual(await question.getAttribute('open'), null);
    assert.equal(await question.locator('p').isVisible(), true);
    await context.close();
    console.log('Navigation, content and expandable FAQs remain available without JavaScript.');
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
