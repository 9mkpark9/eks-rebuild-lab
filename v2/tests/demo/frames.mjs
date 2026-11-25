// 녹화한 영상의 지정한 시각(초) 화면을 frames2/ 에 PNG 로 저장한다 (검토용)
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { pathToFileURL } from 'url';
const v = path.resolve(process.argv[2]);
const ts = process.argv.slice(3).map(Number);
const html = path.resolve('frames-view.html');
fs.writeFileSync(html, `<body style="margin:0;background:#000"><video id="v" src="${pathToFileURL(v).href}" style="width:1600px;height:900px" muted></video></body>`);
fs.mkdirSync('frames2', { recursive: true });
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 1600, height: 900 } });
await p.goto(pathToFileURL(html).href);
await p.waitForFunction(() => document.getElementById('v').readyState >= 1);
for (const t of ts) {
  await p.evaluate((t) => new Promise((r) => { const e = document.getElementById('v'); e.onseeked = () => r(); e.currentTime = t; }), t);
  await p.waitForTimeout(400);
  await p.screenshot({ path: `frames2/t${String(t).padStart(3, '0')}.png` });
}
await b.close();
console.log('ok', ts.length);
