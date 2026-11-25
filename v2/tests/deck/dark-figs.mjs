// 문서의 구성도(SVG)를 어두운 슬라이드용으로: 흰 바탕을 빼고 색을 반전해 투명 PNG 로 (제목 줄은 잘라 낸다)
import { chromium } from 'playwright'; import fs from 'fs'; import path from 'path';
const dir = path.resolve('../../docs/img'); fs.mkdirSync('dark', { recursive: true });
const b = await chromium.launch(); const p = await b.newPage({ deviceScaleFactor: 2 });
for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.svg'))) {
  let svg = fs.readFileSync(path.join(dir, f), 'utf8');
  const [, w, h] = svg.match(/viewBox="0 0 (\d+) (\d+)"/).map(Number);
  svg = svg.replace(/<rect width="\d+" height="\d+" fill="#ffffff"\/>/, '');
  const top = f.startsWith('node') ? 78 : 88;
  await p.setViewportSize({ width: w, height: h });
  await p.setContent(`<html><body style="margin:0;background:transparent"><div style="filter:invert(1) hue-rotate(180deg) saturate(1.3)">${svg}</div></body></html>`);
  await p.screenshot({ path: `dark/${f.replace('.svg', '.png')}`, clip: { x: 0, y: top, width: w, height: h - top }, omitBackground: true });
  console.log(f);
}
await b.close();
