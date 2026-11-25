#!/usr/bin/env node
// 앱 화면을 PNG 로 찍는다. 문서(v2/docs/img/)에 넣는 용도다.
// 이 PC 의 Edge 를 화면 없이(headless) 띄우고 DevTools 프로토콜로 조작한다. 설치할 패키지는 없다 (Node 22 이상의 WebSocket).
//
//   node v2/tests/screenshots.mjs --base-url http://<ALB 주소> --out v2/docs/img --browser "C:/Program Files (x86)/Microsoft/EdgeCore/<버전>/msedge.exe"
//
// 로그인은 시드의 시험 계정(비밀번호 test-only, web/app/src/pages/Login.tsx 에 공개된 값)으로 한다.
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const opt = {};
for (let i = 2; i < process.argv.length; i += 2) opt[process.argv[i].replace(/^--/, '')] = process.argv[i + 1];
const BASE = opt['base-url'].replace(/\/$/, '');
const OUT = opt.out ?? 'v2/docs/img';
const PORT = 9333;
mkdirSync(OUT, { recursive: true });

const profile = mkdtempSync(join(tmpdir(), 'vet2-shot-'));
const browser = spawn(opt.browser, ['--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
  '--no-first-run', '--no-default-browser-check', '--hide-scrollbars', '--lang=ko-KR', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let target;
for (let i = 0; i < 50 && !target; i++) {
  await sleep(200);
  try { target = (await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json()).find((t) => t.type === 'page'); } catch {}
}
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r));
let id = 0;
const pending = new Map();
ws.addEventListener('message', (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
const cdp = (method, params = {}) => new Promise((r) => { const n = ++id; pending.set(n, r); ws.send(JSON.stringify({ id: n, method, params })); });
const js = async (expr) => (await cdp('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true })).result?.result?.value;

await cdp('Page.enable');
await cdp('Emulation.setDeviceMetricsOverride', { width: 1280, height: 860, deviceScaleFactor: 1, mobile: false });

async function shot(name, path, { full = false, wait = 2500 } = {}) {
  await cdp('Page.navigate', { url: BASE + path });
  await sleep(wait);
  let clip;
  if (full) {
    const h = await js('Math.min(document.documentElement.scrollHeight, 2400)');
    clip = { x: 0, y: 0, width: 1280, height: h, scale: 1 };
  }
  const r = await cdp('Page.captureScreenshot', { format: 'png', captureBeyondViewport: full, ...(clip ? { clip } : {}) });
  writeFileSync(join(OUT, name), Buffer.from(r.result.data, 'base64'));
  console.log(`찍음: ${name}  (${path})  제목: ${await js('document.title')}`);
}
async function login(id) {
  await cdp('Network.clearBrowserCookies');
  await cdp('Page.navigate', { url: BASE + '/app/login' });
  await sleep(1500);
  const st = await js(`fetch('/api/auth/login', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({loginId:'${id}', password:'test-only'}), credentials:'include'}).then(r => r.status)`);
  console.log(`로그인 ${id}: ${st}`);
}

await shot('01-intro.png', '/', { full: true });
await shot('02-login.png', '/app/login');
await login('owner001');
await shot('03-owner-home.png', '/app');
await shot('04-owner-reserve.png', '/app/reserve', { full: true });
await shot('05-owner-reservations.png', '/app/reservations');
await login('admin1');
await shot('06-nurse-reservations.png', '/app/nurse', { full: true });
await login('vet1');
await shot('07-director-stats.png', '/app/director/stats', { full: true });

ws.close();
// Windows 에서는 kill() 이 맨 위 프로세스만 끝내고 Edge 의 하위 프로세스가 남는다. 묶음째 끝낸다
if (process.platform === 'win32') spawn('taskkill', ['/PID', String(browser.pid), '/T', '/F'], { stdio: 'ignore' });
else browser.kill();
await sleep(500);
try { rmSync(profile, { recursive: true, force: true }); } catch {}
