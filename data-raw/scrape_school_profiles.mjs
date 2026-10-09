// Save the text of every school in PPS's "School Profiles" Power BI dashboard (2025-26), embedded at
// https://www.pps.net/departments/dataaccountability/data-and-accountability/data-strategy-and-insights/internal-school-profiles
//
// Power BI renders only in a browser, so this drives headless Chrome over the DevTools protocol: it opens
// the public report, clicks each school in the "School" slicer, waits for the page to show that school,
// and writes the visible text to data-raw/pps_reports/school_profiles/<School>.txt.
// parse_school_profiles.py turns those snapshots into data/school_profiles_2025.csv.
//
// Usage: node data-raw/scrape_school_profiles.mjs   (needs Google Chrome; Node 22+)

import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const REPORT = 'https://app.powerbi.com/view?r=eyJrIjoiOWZlNmJhYjQtYzc5YS00MzY5LTk3ODYtMWYxMmQ0YWMyMjIxIiwidCI6ImQwOGRmYzk0LWEyM2MtNDRlNC04YjhkLTRhYmM0MGRkYTlhZSIsImMiOjZ9&pageName=52fe3db4b36f375bbf95';
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PORT = 9341;
const OUT = path.join(path.dirname(fileURLToPath(import.meta.url)), 'pps_reports', 'school_profiles');
const sleep = ms => new Promise(r => setTimeout(r, ms));

fs.mkdirSync(OUT, { recursive: true });
const profile = fs.mkdtempSync(path.join(process.env.TMPDIR || '/tmp', 'pbi-'));
const chrome = spawn(CHROME, ['--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`, 'about:blank'], { stdio: 'ignore' });
let tabs;
for (let i = 0; i < 40 && !tabs; i++) { await sleep(500); try { tabs = await (await fetch(`http://localhost:${PORT}/json/list`)).json(); } catch {} }
if (!tabs) { chrome.kill(); throw new Error('Chrome did not start'); }

const ws = new WebSocket(tabs.find(t => t.type === 'page').webSocketDebuggerUrl);
await new Promise(r => ws.onopen = r);
let id = 0; const pend = {};
ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pend[m.id]) { pend[m.id](m); delete pend[m.id]; } };
const send = (method, params = {}) => new Promise(r => { const i = ++id; pend[i] = r; ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async x => (await send('Runtime.evaluate', { returnByValue: true, expression: x })).result.result.value;

await send('Emulation.setDeviceMetricsOverride', { width: 1400, height: 2400, deviceScaleFactor: 1, mobile: false });
await send('Page.navigate', { url: REPORT });
let schools = [];
for (let i = 0; i < 60 && !schools.length; i++) {
  await sleep(1000);
  schools = await ev(`[...document.querySelectorAll('.slicerItemContainer')].map(e => (e.getAttribute('title') || e.innerText).trim()).filter(Boolean)`) || [];
}
if (schools.length < 50) { chrome.kill(); throw new Error(`slicer has only ${schools.length} schools`); }
console.log(`${schools.length} schools in the slicer`);

const failed = [];
for (const s of schools) {
  await ev(`[...document.querySelectorAll('.slicerItemContainer')].find(e => (e.getAttribute('title') || e.innerText).trim() === ${JSON.stringify(s)}).click()`);
  // wait until the profile header shows this school and the capacity tile has rendered
  let text = '';
  for (let i = 0; i < 40; i++) {
    await sleep(500);
    text = await ev('document.body.innerText') || '';
    const head = text.slice(0, text.indexOf('Address:'));
    if (head.trimEnd().endsWith(s) || new RegExp(`\\n${s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\n\\nLocation`).test(text)) {
      if (/Functional Capacity\n/.test(text)) break;
    }
  }
  await sleep(1500);
  text = await ev('document.body.innerText') || '';
  const ok = text.includes('Address:') && text.includes('Program Type');
  if (!ok) failed.push(s);
  fs.writeFileSync(path.join(OUT, `${s.replace(/[^A-Za-z0-9]+/g, '_')}.txt`), `SELECTED: ${s}\nRETRIEVED: ${new Date().toISOString()}\nSOURCE: ${REPORT}\n\n${text}`);
  process.stdout.write(ok ? '.' : 'x');
}
console.log(`\nsaved ${schools.length - failed.length} profiles to ${OUT}`);
ws.close(); chrome.kill();
if (failed.length) { console.error('failed:', failed.join(', ')); process.exit(1); }
