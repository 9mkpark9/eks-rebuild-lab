#!/usr/bin/env node
// 운영 동작을 재는 동안 계속 요청을 보내고, 실패한 요청을 센다 (③④에서 배포·복구·장애 중에 쓴다).
//
//   node v2/tests/traffic.mjs --base-url http://localhost:28080 --seconds 60 [--workers 5] [--label 이름] [--stop-file 경로]
//
// 화면이 하는 요청을 돌아가며 보낸다: 소개 페이지, 상태 3개, 공지, 그리고 로그인한 보호자의 내 정보·반려동물·내 예약.
// 정해진 시간이 지나거나, --stop-file 의 파일이 생기면(또는 Ctrl+C) 멈추고 결과를 출력한다.
// (Windows 의 Git Bash 에서 kill 은 node 를 바로 끝내 버려 결과를 못 남긴다. 그래서 파일로 멈추게 한다.)
//   - 전체 요청 수, 실패 수
//   - 실패를 경로·응답별로 묶은 것
//   - 실패가 처음과 마지막으로 난 시각 (시작부터 몇 초 뒤인지)
// 200 이 아닌 응답, 응답 없음(제한 시간 5초), 로그인 풀림(401)을 모두 실패로 센다.
const opt = { workers: '5', seconds: '60', label: '' };
for (let i = 2; i < process.argv.length; i += 2) opt[process.argv[i].replace(/^--/, '')] = process.argv[i + 1];
const base = (opt['base-url'] ?? '').replace(/\/$/, '');
if (!base) { console.error('--base-url 이 필요합니다'); process.exit(2); }
const t0 = Date.now();
const sec = () => ((Date.now() - t0) / 1000).toFixed(1);
const PATHS = [
  ['GET', '/', false], ['GET', '/api/status/auth', false], ['GET', '/api/status/clinic', false],
  ['GET', '/api/status/reservation', false], ['GET', '/api/notices', false],
  ['GET', '/api/auth/me', true], ['GET', '/api/pets', true], ['GET', '/api/reservations/me', true],
];
let total = 0, failed = 0, first = null, last = null, stop = false;
const groups = new Map();

async function call(method, path, cookie, body) {
  const headers = { Accept: 'application/json' };
  if (cookie) headers.Cookie = cookie;
  if (body) headers['Content-Type'] = 'application/json';
  try {
    const res = await fetch(base + path, { method, headers, body: body && JSON.stringify(body), signal: AbortSignal.timeout(5000) });
    await res.arrayBuffer();
    const m = /SESSION=([^;]+)/.exec(res.headers.get('set-cookie') ?? '');
    return { code: String(res.status), cookie: m ? `SESSION=${m[1]}` : null };
  } catch (e) {
    return { code: e.name === 'TimeoutError' ? '응답 없음' : `연결 실패(${e.cause?.code ?? e.message})` };
  }
}

async function login(n) {
  for (;;) {
    const r = await call('POST', '/api/auth/login', null, { loginId: `owner${String(280 + n).padStart(3, '0')}`, password: 'test-only' });
    if (r.code === '200' && r.cookie) return r.cookie;
    // 로그인 실패도 실패로 센다 (세지 않으면 로그인을 기다리는 동안의 장애가 숨는다)
    total++; failed++;
    const k = `/api/auth/login → ${r.code}`;
    groups.set(k, (groups.get(k) ?? 0) + 1);
    first ??= sec(); last = sec();
    if (stop || Date.now() - t0 > Number(opt.seconds) * 1000) return null;
    await new Promise((ok) => setTimeout(ok, 500));
  }
}

async function worker(n) {
  let cookie = await login(n);
  for (let i = n; !stop && Date.now() - t0 < Number(opt.seconds) * 1000; i++) {
    const [method, path, auth] = PATHS[i % PATHS.length];
    const r = await call(method, path, auth ? cookie : null);
    total++;
    if (r.code !== '200') {
      failed++;
      const k = `${path} → ${r.code}`;
      groups.set(k, (groups.get(k) ?? 0) + 1);
      first ??= sec(); last = sec();
      if (r.code === '401' && auth) cookie = await login(n);   // 로그인이 풀렸으면 다시 한다
    }
    await new Promise((ok) => setTimeout(ok, 50));
  }
}

function report() {
  console.log(`[트래픽${opt.label ? ' ' + opt.label : ''}] ${sec()}초 동안 요청 ${total}건, 실패 ${failed}건${failed ? ` (처음 ${first}초, 마지막 ${last}초)` : ''}`);
  for (const [k, v] of [...groups].sort((a, b) => b[1] - a[1])) console.log(`    ${k}: ${v}건`);
}
import { existsSync } from 'node:fs';
if (opt['stop-file']) setInterval(() => { if (existsSync(opt['stop-file'])) stop = true; }, 200).unref();
process.on('SIGTERM', () => { stop = true; });
process.on('SIGINT', () => { stop = true; });
await Promise.all(Array.from({ length: Number(opt.workers) }, (_, n) => worker(n)));
report();
process.exit(failed ? 1 : 0);
