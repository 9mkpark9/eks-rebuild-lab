#!/usr/bin/env node
// v2/tests/cap.sh 가 남긴 기록(v2/_run/capture/*.txt)을 터미널 모양 PNG 로 만든다.
// 이 PC 의 Edge 를 화면 없이 띄워 찍는다 (설치할 패키지 없음, Node 22 이상).
//
//   node v2/tests/render.mjs --browser "<msedge.exe>" [--only w1-07-scenario,req3-...] [--ppt]
//     문서용: v2/docs/img/cap/<이름>.png      가로 1200, 높이는 내용만큼 (최대 2400)
//     --ppt : v2/docs/img/ppt/<이름>.png      1600 x 900 (16:9). 줄이 넘치면 앞뒤를 남기고 가운데를 접는다
//
// 기록 파일의 머리: "#title: 제목", "#env: 환경 · 날짜", 그 뒤 "$ 명령" 과 출력. "#exit: N" 은 실패로 표시한다.
// 강조: 통과/Ready/Running/Bound/healthy 는 초록, 실패/ERROR/error/Forbidden/denied/Pending/BackOff 는 빨강.
import { spawn } from 'node:child_process';
import { readFileSync, writeFileSync, readdirSync, mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { join, basename } from 'node:path';
import { tmpdir } from 'node:os';

const opt = { ppt: false };
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a === '--ppt') opt.ppt = true;
  else opt[a.replace(/^--/, '')] = process.argv[++i];
}
const SRC = 'v2/_run/capture';
const OUT = opt.ppt ? 'v2/docs/img/ppt' : 'v2/docs/img/cap';
mkdirSync(OUT, { recursive: true });
const only = opt.only ? opt.only.split(',') : null;
const files = readdirSync(SRC).filter((f) => f.endsWith('.txt')).filter((f) => !only || only.includes(basename(f, '.txt'))).sort();

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const GOOD = /(\[통과\]|통과 \d+ \/ 실패 0|\bReady\b|\bRunning\b|\bBound\b|healthy|BUILD SUCCESSFUL|초기화 끝|condition met|evicted|drained|successfully rolled out|Successfully created)/;
const BAD = /(\[실패\]|ERROR|[Ee]rror|Forbidden|denied|Pending|BackOff|ImagePull|Too many connections|Cannot evict|NotReady|Terminating|실패 [1-9]\d*건|응답 없음|not found|BUILD FAILED)/;
function lineHtml(l) {
  if (l.startsWith('$ ')) return `<div class="cmd"><span class="ps">$</span> ${esc(l.slice(2))}</div>`;
  const cls = BAD.test(l) && !/실패 0/.test(l) ? 'bad' : GOOD.test(l) ? 'good' : l.startsWith('■') ? 'sec' : '';
  return `<div class="${cls}">${esc(l) || '&nbsp;'}</div>`;
}
function page(txt, ppt) {
  let lines = txt.replace(/\r/g, '').split('\n');
  const meta = {};
  lines = lines.filter((l) => { const m = l.match(/^#(title|env|exit): ?(.*)$/); if (m) { meta[m[1]] = m[2]; return false; } return true; });
  while (lines.length && !lines.at(-1).trim()) lines.pop();
  const maxLines = ppt ? 34 : 110;
  if (lines.length > maxLines) {
    const head = Math.ceil(maxLines * 0.45), tail = maxLines - head - 1;
    lines = [...lines.slice(0, head), `… (가운데 ${lines.length - head - tail}줄 생략. 전체는 v2/_run/capture 의 원본) …`, ...lines.slice(-tail)];
  }
  const fs = ppt ? 19 : 14;
  return `<!doctype html><html><head><meta charset="utf-8"><style>
  html,body{margin:0;background:#0b1220}
  .win{width:${ppt ? 1600 : 1200}px;${ppt ? 'height:900px;' : ''}box-sizing:border-box;background:#0f172a;color:#e2e8f0;font-family:'Cascadia Mono','D2Coding',Consolas,'Malgun Gothic',monospace;display:flex;flex-direction:column}
  .bar{display:flex;align-items:center;gap:12px;padding:${ppt ? '16px 26px' : '11px 18px'};background:#1e293b;border-bottom:1px solid #334155}
  .dot{width:13px;height:13px;border-radius:50%;display:inline-block}
  .t{font-family:'Malgun Gothic','Apple SD Gothic Neo',sans-serif;font-weight:700;font-size:${ppt ? 27 : 17}px;color:#f8fafc;flex:1}
  .env{font-size:${ppt ? 15 : 12}px;color:#94a3b8}
  .body{padding:${ppt ? '20px 30px' : '14px 20px'};font-size:${fs}px;line-height:1.45;white-space:pre;overflow:hidden;flex:1}
  .cmd{color:#7dd3fc}.ps{color:#a78bfa}.good{color:#4ade80}.bad{color:#f87171}.sec{color:#fbbf24;font-weight:700}
  .exit{padding:6px 20px 12px;color:#f87171;font-size:${fs}px}
  </style></head><body><div class="win"><div class="bar"><span class="dot" style="background:#ef4444"></span><span class="dot" style="background:#f59e0b"></span><span class="dot" style="background:#22c55e"></span>
  <span class="t">${esc(meta.title || '')}</span><span class="env">${esc(meta.env || '')}</span></div>
  <div class="body">${lines.map(lineHtml).join('')}</div>${meta.exit ? `<div class="exit">종료 코드 ${esc(meta.exit)}</div>` : ''}</div></body></html>`;
}

const PORT = 9335;
const profile = mkdtempSync(join(tmpdir(), 'vet2-render-'));
const browser = spawn(opt.browser, ['--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`, '--no-first-run', '--hide-scrollbars', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let target;
for (let i = 0; i < 100 && !target; i++) { await sleep(300); try { target = (await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json()).find((t) => t.type === 'page'); } catch {} }
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r));
let id = 0; const pending = new Map();
ws.addEventListener('message', (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
const cdp = (method, params = {}) => new Promise((r) => { const n = ++id; pending.set(n, r); ws.send(JSON.stringify({ id: n, method, params })); });
await cdp('Page.enable');
const W = opt.ppt ? 1600 : 1200;
await cdp('Emulation.setDeviceMetricsOverride', { width: W, height: 900, deviceScaleFactor: opt.ppt ? 1 : 1.5, mobile: false });
const frame = (await cdp('Page.getFrameTree')).result.frameTree.frame.id;

for (const f of files) {
  const html = page(readFileSync(join(SRC, f), 'utf8'), opt.ppt);
  await cdp('Page.setDocumentContent', { frameId: frame, html });
  await sleep(250);
  const h = opt.ppt ? 900 : Math.min((await cdp('Runtime.evaluate', { expression: 'document.querySelector(".win").scrollHeight', returnByValue: true })).result.result.value, 2400);
  const r = await cdp('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true, clip: { x: 0, y: 0, width: W, height: h, scale: 1 } });
  const out = join(OUT, basename(f, '.txt') + '.png');
  writeFileSync(out, Buffer.from(r.result.data, 'base64'));
  console.log(`그림: ${out}`);
}
ws.close();
if (process.platform === 'win32') spawn('taskkill', ['/PID', String(browser.pid), '/T', '/F'], { stdio: 'ignore' }); else browser.kill();
await sleep(500);
try { rmSync(profile, { recursive: true, force: true }); } catch {}
