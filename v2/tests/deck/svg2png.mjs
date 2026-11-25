import { chromium } from 'playwright'; import fs from 'fs'; import path from 'path'; import { pathToFileURL } from 'url';
const dir = path.resolve('../../docs/img'); const b = await chromium.launch(); const p = await b.newPage({ deviceScaleFactor: 2 });
for (const f of fs.readdirSync(dir).filter(f=>f.endsWith('.svg'))) {
  const vb = fs.readFileSync(path.join(dir,f),'utf8').match(/viewBox="0 0 (\d+) (\d+)"/); const w=+vb[1], h=+vb[2];
  await p.setViewportSize({width:w,height:h}); await p.goto(pathToFileURL(path.join(dir,f)).href);
  const top = f.startsWith('node')?78:88; await p.screenshot({path:`fig/c-${f.replace('.svg','.png')}`, clip:{x:0,y:top,width:w,height:h-top}}); console.log(f,w,h); }
await b.close();
