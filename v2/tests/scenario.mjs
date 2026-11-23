#!/usr/bin/env node
// 보듬 동물병원 — 시나리오 테스트 (①~④ 모든 단계에서 같은 파일을 쓴다)
//
// 화면이 쓰는 API 를 실제로 부르고 통과/실패를 출력한다. 근거는 소스의 컨트롤러와 web/app/src/api.ts 다.
// 필요한 것은 Node 22 이상뿐이다 (내장 fetch 사용, 설치할 패키지 없음).
//
//   ① 서비스 3개에 직접 (웹 서버 없음)
//     node v2/tests/scenario.mjs --auth-url http://127.0.0.1:28081 --clinic-url http://127.0.0.1:28082 \
//                                --reservation-url http://127.0.0.1:28083 --db-container v2-mysql
//   ②③④ 웹 서버를 거쳐서 (주소 하나)
//     node v2/tests/scenario.mjs --base-url http://localhost:28080 --db-container v2-mysql-1
//   도커 네트워크 안에서 (PC 의 게시 포트를 거치지 않는다. ② 문서 C-11)
//     docker run --rm -i --network v2_default node:22-alpine node --input-type=module - --base-url http://web:8080 < v2/tests/scenario.mjs
//
// --db-container NAME   DB 계정 경계(11번)를 확인한다. 그 컨테이너 안의 mysql 로 서비스 계정 접속을 시도한다.
//                       비밀번호는 환경 변수 DB_AUTH_PASSWORD, DB_CLINIC_PASSWORD, DB_RESERVATION_PASSWORD 로 준다.
// --db-exec "CMD"       --db-container 대신, DB 안에서 명령을 실행할 앞부분을 준다 (쿠버네티스용).
//                       예: --db-exec "kubectl -n vet2 exec mysql-0 --"
//
// 만든 예약은 끝에서 취소하므로 여러 번 돌려도 된다. 실패 수를 종료 코드로 돌려준다 (0 = 전부 통과).
import { spawnSync } from 'node:child_process';

const opt = {};
for (let i = 2; i < process.argv.length; i += 2) opt[process.argv[i].replace(/^--/, '')] = process.argv[i + 1];
const direct = !opt['base-url'];
const strip = (u) => (u ?? '').replace(/\/$/, '');
const URLS = direct
  ? { auth: strip(opt['auth-url']), clinic: strip(opt['clinic-url']), reservation: strip(opt['reservation-url']) }
  : { auth: strip(opt['base-url']), clinic: strip(opt['base-url']), reservation: strip(opt['base-url']) };
if (!URLS.auth || !URLS.clinic || !URLS.reservation) {
  console.error('주소가 필요합니다: --base-url 또는 --auth-url, --clinic-url, --reservation-url');
  process.exit(2);
}
const PASSWORD = 'test-only'; // 시드의 테스트 계정 공통 비밀번호 (web/app/src/pages/Login.tsx)

// 경로 → 맡은 서비스. 컨트롤러의 @RequestMapping 을 옮긴 것이다. 직접 실행에서는 이 표가 웹 서버의 역할을 대신한다.
function owner(path) {
  if (path.startsWith('/api/auth') || path.startsWith('/api/status/auth')) return 'auth';
  if (/^\/api\/(pets|notices|slots|admin\/notices|status\/clinic)/.test(path)) return 'clinic';
  return 'reservation';
}

class Client {
  cookie = null;
  async req(method, path, body, base) {
    const headers = { Accept: 'application/json' };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (this.cookie) headers.Cookie = this.cookie;
    let res;
    try {
      res = await fetch((base ?? URLS[owner(path)]) + path, {
        method, headers, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000),
      });
    } catch (e) {
      return { status: 0, json: null, text: String(e.cause?.code ?? e.message), headers: new Headers() };
    }
    for (const c of res.headers.getSetCookie()) {
      const m = /^SESSION=([^;]*)/.exec(c);
      if (m) this.cookie = m[1] ? `SESSION=${m[1]}` : null;
    }
    const text = await res.text();
    let json = null;
    try { json = JSON.parse(text); } catch { /* JSON 이 아닌 응답 */ }
    return { status: res.status, json, text, headers: res.headers };
  }
  get(path, base) { return this.req('GET', path, undefined, base); }
  post(path, body) { return this.req('POST', path, body); }
  put(path, body) { return this.req('PUT', path, body); }
  del(path) { return this.req('DELETE', path); }
  login(id, password = PASSWORD) { return this.post('/api/auth/login', { loginId: id, password }); }
}

let pass = 0, fail = 0;
function check(id, title, ok, detail = '') {
  if (ok) pass++; else fail++;
  console.log(`[${ok ? '통과' : '실패'}] ${id} ${title}${detail ? ' — ' + detail : ''}`);
  return ok;
}
// 앞 단계가 실패해 뒤 단계가 이어 갈 수 없을 때(예: 로그인 실패)도 실패로 세고 끝낸다
const abort = (e) => {
  console.log(`[실패] 이후 단계를 진행할 수 없어 중단 — ${e?.message ?? e}`);
  console.log(`\n결과: 통과 ${pass} / 실패 ${fail + 1} (중단)`);
  process.exit(Math.min(fail + 1, 100));
};
process.on('uncaughtException', abort);
process.on('unhandledRejection', abort);
const section = (s) => console.log(`\n■ ${s}`);
const st = (r) => (r.status === 0 ? `0(${r.text})` : `${r.status}${r.json?.code ? ' ' + r.json.code : ''}`);

// 병원 현지 시각(KST) 기준 날짜
const kst = (ms = Date.now()) => new Date(ms + 9 * 3600 * 1000).toISOString();
const dayPlus = (n) => kst(Date.now() + n * 86400 * 1000).slice(0, 10);

console.log(`시나리오 테스트  ${kst().slice(0, 19).replace('T', ' ')} KST`);
console.log(direct ? `대상: 서비스 직접  auth ${URLS.auth}  clinic ${URLS.clinic}  reservation ${URLS.reservation}` : `대상: 웹 서버 경유  ${URLS.auth}`);

const anon = new Client();

// ── 0. 화면 (웹 서버를 거칠 때만) ───────────────────────────────────────
if (!direct) {
  section('0. 화면');
  const base = URLS.auth;
  const page = async (path) => { const r = await anon.get(path, base); return { ...r, type: r.headers.get('content-type') ?? '' }; };
  const home = await page('/');
  check('0-1', '소개 페이지 /', home.status === 200 && home.type.includes('text/html') && home.text.includes('보듬 동물병원'), `${home.status} ${home.type}`);
  const about = await page('/about');
  check('0-2', '확장자 없는 주소 /about', about.status === 200 && about.type.includes('text/html'), `${about.status} ${about.type}`);
  const css = await page('/assets/css/site.css');
  check('0-3', '정적 파일 /assets/css/site.css', css.status === 200 && css.type.includes('text/css'), `${css.status} ${css.type}`);
  const app = await page('/app/');
  const js = /src="(\/app\/assets\/[^"]+\.js)"/.exec(app.text)?.[1];
  check('0-4', '예약 화면 /app/', app.status === 200 && app.text.includes('id="root"') && !!js, `${app.status} 스크립트 ${js ?? '없음'}`);
  const bundle = await page(js ?? '/app/assets/none.js');
  check('0-5', '예약 화면의 스크립트 파일', bundle.status === 200 && bundle.type.includes('javascript'), `${bundle.status} ${bundle.type} ${Math.round(bundle.text.length / 1024)}KB`);
  const deep = await page('/app/reserve');
  check('0-6', '예약 화면 안쪽 주소 /app/reserve 도 같은 화면을 준다', deep.status === 200 && deep.text.includes('id="root"'), `${deep.status}`);
  const none = await page('/no-such-page');
  check('0-7', '없는 페이지는 404', none.status === 404, `${none.status}`);
  const api = await page('/api/status/auth');
  check('0-8', '응답에 웹 서버 이름과 버전이 실린다', !!api.headers.get('x-web-node') && !!api.headers.get('x-web-version'),
    `X-Web-Node=${api.headers.get('x-web-node') ? '있음' : '없음'} X-Web-Version=${api.headers.get('x-web-version') ?? '없음'}`);
}

// ── 1. 상태 ─────────────────────────────────────────────────────────────
section('1. 상태');
for (const s of direct ? ['auth', 'clinic', 'reservation'] : ['auth']) {
  const r = await anon.get('/health', URLS[s]);
  check('1-1', direct ? `${s} /health` : '웹 서버 /health', r.status === 200 && r.text.trim() === 'ok', `${r.status} "${r.text.trim().slice(0, 20)}"`);
}
for (const s of ['auth', 'clinic', 'reservation']) {
  const r = await anon.get(`/api/status/${s}`);
  check('1-2', `/api/status/${s}`, r.status === 200 && r.json?.service === s && r.json?.status === 'ok' && !!r.headers.get('x-served-by') && !!r.headers.get('x-app-version'),
    `${r.status} version=${r.json?.version} X-Served-By=${r.headers.get('x-served-by') ? '있음' : '없음'}`);
}

// ── 2. 로그인 없이 조회 ─────────────────────────────────────────────────
section('2. 로그인 없이 조회');
{
  const r = await anon.get('/api/notices');
  check('2-1', '공지 목록', r.status === 200 && Array.isArray(r.json) && r.json.length > 0, `${r.status} ${r.json?.length ?? 0}건`);
  const id = r.json?.[0]?.noticeId;
  const d = await anon.get(`/api/notices/${id}`);
  check('2-2', '공지 상세 (본문 포함)', d.status === 200 && typeof d.json?.content === 'string' && d.json.content.length > 0, `${d.status} "${(d.json?.title ?? '').slice(0, 24)}"`);
  const bad = await anon.get('/api/slots?date=2026-13-99');
  check('2-3', '잘못된 날짜는 400', bad.status === 400 && bad.json?.code === 'INVALID', st(bad));
}
// 내일 이후에서 일반 진료 빈 시간이 3개 이상 있는 첫 날을 고른다
let DAY = null, free = [];
for (let n = 1; n <= 13 && !DAY; n++) {
  const r = await anon.get(`/api/slots?date=${dayPlus(n)}&type=GENERAL`);
  if (r.status === 200 && r.json.length >= 3) { DAY = dayPlus(n); free = r.json; }
}
check('2-4', '예약 가능 시간 조회', !!DAY, DAY ? `${DAY} 일반 진료 빈 시간 ${free.length}개` : '빈 시간이 있는 날을 찾지 못함');
if (!DAY) { console.log('\n빈 시간이 없어 이후 단계를 진행할 수 없습니다.'); process.exit(fail || 1); }
const [S1, S2] = free;
const slotVisible = async (slotId, type = 'GENERAL') => {
  const r = await anon.get(`/api/slots?date=${DAY}&type=${type}`);
  return r.status === 200 && r.json.some((s) => s.slotId === slotId);
};

// ── 3. 로그인과 서비스 간 세션 ──────────────────────────────────────────
section('3. 로그인과 서비스 간 세션');
{
  const a = await anon.get('/api/pets'), b = await anon.get('/api/reservations/me');
  check('3-1', '로그인 전에는 401', a.status === 401 && b.status === 401 && a.json?.code === 'UNAUTHORIZED', `clinic ${st(a)}, reservation ${st(b)}`);
  const w = await new Client().login('owner250', 'wrong-password');
  check('3-2', '틀린 비밀번호는 401', w.status === 401 && w.json?.code === 'INVALID_CREDENTIALS', st(w));
}
const me = new Client();
{
  const r = await me.login('owner250');
  check('3-3', '보호자 로그인 (auth)', r.status === 200 && r.json?.role === 'OWNER' && !!me.cookie, `${st(r)} role=${r.json?.role} 쿠키=${me.cookie ? '받음' : '없음'}`);
  const m = await me.get('/api/auth/me');
  check('3-4', '내 정보 (auth)', m.status === 200 && m.json?.loginId === 'owner250', `${st(m)} loginId=${m.json?.loginId}`);
  const p = await me.get('/api/pets');
  check('3-5', 'auth 에서 받은 세션을 clinic 이 읽는다', p.status === 200 && Array.isArray(p.json), `${st(p)} 반려동물 ${p.json?.length ?? '-'}마리`);
  const v = await me.get('/api/reservations/me');
  check('3-6', 'auth 에서 받은 세션을 reservation 이 읽는다', v.status === 200 && Array.isArray(v.json), `${st(v)} 예약 ${v.json?.length ?? '-'}건`);
}

// ── 4. 예약: 등록 → 조회 → 변경 ─────────────────────────────────────────
section('4. 예약: 등록 → 조회 → 변경');
let petId, rid;
{
  // 테스트용 반려동물은 한 번만 만들고 다음부터는 다시 쓴다
  const list = (await me.get('/api/pets')).json ?? [];
  let pet = list.find((p) => p.name === '시험이');
  if (!pet) {
    const c = await me.post('/api/pets', { name: '시험이', species: 'DOG', age: 1 });
    check('4-1', '반려동물 등록', c.status === 201 && c.json?.petId > 0, `${st(c)} petId=${c.json?.petId}`);
    pet = c.json;
  } else check('4-1', '반려동물 조회 (이전 실행에서 등록한 것)', true, `petId=${pet.petId}`);
  petId = pet?.petId;
  const age = ((pet?.age ?? 1) % 20) + 1;
  const u = await me.put(`/api/pets/${petId}`, { name: '시험이', species: 'DOG', age });
  check('4-2', '반려동물 수정', u.status === 200 && u.json?.age === age, `${st(u)} age ${pet?.age}→${u.json?.age}`);

  const c = await me.post('/api/reservations', { petId, slotId: S1.slotId });
  rid = c.json?.reservationId;
  check('4-3', '예약 신청', c.status === 201 && c.json?.status === 'REQUESTED' && c.json?.slotId === S1.slotId, `${st(c)} 예약 ${rid} ${c.json?.startAt} ${c.json?.status}`);
  const diff = Math.abs(Date.parse(c.json?.createdAt + '+09:00') - Date.now()) / 1000;
  check('4-4', '신청 시각이 병원 현지 시각으로 기록된다', diff < 120, `createdAt=${c.json?.createdAt} (지금과 ${Math.round(diff)}초 차이)`);
  const mine = await me.get('/api/reservations/me');
  check('4-5', '내 예약 목록에 보인다', mine.json?.some((x) => x.reservationId === rid && x.status === 'REQUESTED'), `${st(mine)} ${mine.json?.length}건`);
  check('4-6', '잡힌 시간은 예약 가능 목록에서 빠진다', !(await slotVisible(S1.slotId)));

  const other = new Client();
  await other.login('owner251');
  const otherPet = (await other.get('/api/pets')).json?.[0]?.petId;
  const t = await other.post('/api/reservations', { petId: otherPet, slotId: S1.slotId });
  check('4-7', '다른 보호자가 같은 시간을 신청하면 409', t.status === 409 && t.json?.code === 'SLOT_TAKEN', st(t));
  const sd = await me.post('/api/reservations', { petId, slotId: S2.slotId });
  check('4-8', '같은 반려동물을 같은 날 또 신청하면 409', sd.status === 409 && sd.json?.code === 'PET_SAME_DAY', st(sd));
  const oc = await other.del(`/api/reservations/${rid}`);
  check('4-9', '남의 예약은 취소할 수 없다 (404)', oc.status === 404, st(oc));
  const oa = await other.get(`/api/admin/reservations?date=${DAY}`);
  check('4-10', '보호자는 직원 API 를 쓸 수 없다 (403)', oa.status === 403 && oa.json?.code === 'FORBIDDEN', st(oa));

  const ch = await me.put(`/api/reservations/${rid}`, { slotId: S2.slotId });
  check('4-11', '예약 시간 변경', ch.status === 200 && ch.json?.slotId === S2.slotId, `${st(ch)} ${S1.startAt} → ${ch.json?.startAt}`);
  check('4-12', '변경 뒤 원래 시간은 다시 열린다', (await slotVisible(S1.slotId)) && !(await slotVisible(S2.slotId)));
}

// ── 5. 직원: 간호사와 원장 ──────────────────────────────────────────────
section('5. 직원: 간호사와 원장');
const nurse = new Client(), director = new Client();
{
  const l = await nurse.login('admin1');
  const list = await nurse.get(`/api/admin/reservations?date=${DAY}`);
  check('5-1', '간호사가 그날 예약 현황에서 본다', l.json?.role === 'NURSE' && list.json?.some((x) => x.reservationId === rid && x.ownerLoginId === 'owner250'), `${st(list)} ${list.json?.length}건`);
  const ap = await nurse.post(`/api/admin/reservations/${rid}/approve`);
  check('5-2', '간호사 승인', ap.status === 200 && ap.json?.status === 'CONFIRMED', `${st(ap)} ${ap.json?.status}`);
  const ap2 = await nurse.post(`/api/admin/reservations/${rid}/approve`);
  check('5-3', '이미 승인한 예약을 또 승인하면 409', ap2.status === 409 && ap2.json?.code === 'NOT_REQUESTED', st(ap2));
  const seen = await me.get('/api/reservations/me');
  check('5-4', '보호자 화면에서도 확정으로 보인다', seen.json?.find((x) => x.reservationId === rid)?.status === 'CONFIRMED');

  const nc = await nurse.post('/api/admin/notices', { category: 'NOTICE', title: '시나리오 테스트 공지', content: '자동 테스트가 만들고 지웁니다.', pinned: false });
  const nid = nc.json?.noticeId;
  const nv = await anon.get(`/api/notices/${nid}`);
  check('5-5', '공지 등록', nc.status === 201 && nv.status === 200, `${st(nc)} noticeId=${nid}`);
  const nd = await nurse.del(`/api/admin/notices/${nid}`);
  const ng = await anon.get(`/api/notices/${nid}`);
  check('5-6', '공지 삭제', nd.status === 204 && ng.status === 404, `삭제 ${nd.status}, 다시 조회 ${ng.status}`);
  const np = await nurse.get('/api/pets'), ns = await nurse.get('/api/director/stats');
  check('5-7', '간호사는 보호자·원장 API 를 쓸 수 없다 (403)', np.status === 403 && ns.status === 403, `pets ${st(np)}, director ${st(ns)}`);

  const dl = await director.login('vet1');
  const sch = await director.get(`/api/director/schedule?date=${DAY}`);
  check('5-8', '원장이 자기 진료 일정을 본다', dl.json?.role === 'DIRECTOR' && sch.status === 200 && sch.json?.length > 0 && sch.json.every((s) => 'isOpen' in s), `${st(sch)} 슬롯 ${sch.json?.length}개`);
  const stats = await director.get('/api/director/stats');
  check('5-9', '병원 현황 집계', stats.status === 200 && stats.json?.totals?.slots > 0 && stats.json?.byVet?.length === 3, `${st(stats)} 슬롯 ${stats.json?.totals?.slots}, 활성 예약 ${stats.json?.totals?.active}`);
  const mineFree = sch.json?.find((s) => !s.reservation && s.isOpen && s.slotId !== S1.slotId && s.slotId !== S2.slotId);
  const cl = await director.put(`/api/director/slots/${mineFree?.slotId}`, { isOpen: false });
  const hidden = !(await slotVisible(mineFree?.slotId, mineFree?.visitType));
  check('5-10', '원장이 자기 시간을 닫으면 예약 가능 목록에서 빠진다', cl.status === 200 && cl.json?.isOpen === false && hidden, `${st(cl)} slot ${mineFree?.slotId} ${mineFree?.startAt}`);
  const op = await director.put(`/api/director/slots/${mineFree?.slotId}`, { isOpen: true });
  check('5-11', '다시 열면 목록에 돌아온다', op.status === 200 && (await slotVisible(mineFree?.slotId, mineFree?.visitType)), st(op));
  const others = (await anon.get(`/api/slots?date=${DAY}`)).json?.find((s) => s.vetId !== 1);
  const fb = await director.put(`/api/director/slots/${others?.slotId}`, { isOpen: false });
  check('5-12', '다른 원장의 시간은 바꿀 수 없다 (403)', fb.status === 403, `${st(fb)} slot ${others?.slotId} (vet ${others?.vetId})`);
  const da = await director.get(`/api/admin/reservations?date=${DAY}`);
  check('5-13', '원장은 간호사 API 를 쓸 수 없다 (403)', da.status === 403, st(da));
}

// ── 6. 취소 ─────────────────────────────────────────────────────────────
section('6. 취소');
{
  const c = await me.del(`/api/reservations/${rid}`);
  check('6-1', '보호자 취소', c.status === 204, st(c));
  const mine = await me.get('/api/reservations/me');
  check('6-2', '취소 상태로 남는다', mine.json?.find((x) => x.reservationId === rid)?.status === 'CANCELLED');
  check('6-3', '취소한 시간은 다시 열린다', await slotVisible(S2.slotId));
  const c2 = await me.del(`/api/reservations/${rid}`);
  check('6-4', '이미 취소한 예약을 또 취소하면 409', c2.status === 409 && c2.json?.code === 'CANCELLED', st(c2));
}

// ── 7. 동시 신청 (중복 예약 방지) ───────────────────────────────────────
section('7. 동시 신청');
{
  const N = 10;
  const clients = [];
  for (let i = 0; i < N; i++) {
    const c = new Client();
    await c.login(`owner${201 + i}`);
    c.pet = (await c.get('/api/pets')).json?.[0]?.petId;
    clients.push(c);
  }
  const results = await Promise.all(clients.map((c) => c.post('/api/reservations', { petId: c.pet, slotId: S1.slotId })));
  const tally = {};
  for (const r of results) { const k = st(r); tally[k] = (tally[k] ?? 0) + 1; }
  const wins = results.filter((r) => r.status === 201);
  const rest409 = results.filter((r) => r.status === 409).length;
  check('7-1', `보호자 ${N}명이 같은 시간을 동시에 신청하면 1명만 성공`, wins.length === 1 && rest409 === N - 1, Object.entries(tally).map(([k, v]) => `${k} × ${v}`).join(', '));
  let cleaned = wins.length > 0;
  for (let i = 0; i < N; i++) if (results[i].status === 201) cleaned &&= (await clients[i].del(`/api/reservations/${results[i].json.reservationId}`)).status === 204;
  check('7-2', '성공한 예약을 취소해 원래대로 돌린다', cleaned && (await slotVisible(S1.slotId)));
}

// ── 8. 로그인 시도 제한 (Redis 카운터) ──────────────────────────────────
section('8. 로그인 시도 제한');
{
  const c = new Client();
  const codes = [];
  for (let i = 0; i < 6; i++) codes.push((await c.login('owner299', 'wrong-password')).status);
  check('8-1', '틀린 비밀번호 5번 뒤에는 429', codes[5] === 429, codes.join(' → '));
}

// ── 9. 로그아웃 ─────────────────────────────────────────────────────────
section('9. 로그아웃');
{
  const old = me.cookie;
  const lo = await me.post('/api/auth/logout');
  check('9-1', '로그아웃', lo.status === 204, st(lo));
  me.cookie = old; // 지워진 세션의 쿠키를 그대로 다시 보낸다
  const a = await me.get('/api/auth/me'), p = await me.get('/api/pets'), r = await me.get('/api/reservations/me');
  check('9-2', '로그아웃한 쿠키는 세 서비스 모두에서 401', a.status === 401 && p.status === 401 && r.status === 401, `auth ${a.status}, clinic ${p.status}, reservation ${r.status}`);
}

// ── 10. 서비스가 맡은 경로만 답하는가 (직접 실행에서만) ─────────────────
if (direct) {
  section('10. 서비스 경계');
  const a = await anon.get('/api/notices', URLS.auth), c = await anon.get('/api/auth/me', URLS.clinic), r = await anon.get('/api/slots?date=' + DAY, URLS.reservation);
  check('10-1', '남이 맡은 경로를 물으면 404', a.status === 404 && c.status === 404 && r.status === 404, `auth←/api/notices ${a.status}, clinic←/api/auth/me ${c.status}, reservation←/api/slots ${r.status}`);
}

// ── 11. DB 계정 경계 ────────────────────────────────────────────────────
const dbExec = opt['db-exec'] ? opt['db-exec'].split(/\s+/) : opt['db-container'] ? ['docker', 'exec', opt['db-container']] : null;
if (dbExec) {
  section('11. DB 계정 경계');
  const pw = { auth: process.env.DB_AUTH_PASSWORD, clinic: process.env.DB_CLINIC_PASSWORD, reservation: process.env.DB_RESERVATION_PASSWORD };
  const run = (svc, query) => {
    const r = spawnSync(dbExec[0], [...dbExec.slice(1), 'env', `MYSQL_PWD=${pw[svc]}`, 'mysql', `-uvet_${svc}`, '-N', '-e', query], { encoding: 'utf8' });
    const err = (r.stderr ?? '').split('\n').find((l) => l.startsWith('ERROR')) ?? '';
    return { ok: r.status === 0, out: (r.stdout ?? '').trim(), err: err.replace(/^ERROR (\d+) \(\w+\) at line \d+: /, 'ERROR $1: ').replace(/ to user .*| in 'field list'/, '') };
  };
  const allow = (id, title, svc, query) => { const r = run(svc, query); check(id, title, r.ok, r.ok ? `결과 ${r.out}` : r.err); };
  const deny = (id, title, svc, query) => { const r = run(svc, query); check(id, title, !r.ok && /denied|Unknown column/.test(r.err), r.ok ? `막히지 않음 (결과 ${r.out})` : r.err); };
  allow('11-1', 'auth 계정은 자기 사용자 테이블을 읽는다', 'auth', 'SELECT COUNT(*) FROM vet_auth.users');
  deny('11-2', 'auth 계정은 반려동물을 읽지 못한다', 'auth', 'SELECT COUNT(*) FROM vet_clinic.pets');
  deny('11-3', 'clinic 계정은 사용자를 읽지 못한다', 'clinic', 'SELECT COUNT(*) FROM vet_auth.users');
  deny('11-4', 'clinic 계정은 예약을 읽지 못한다', 'clinic', 'SELECT COUNT(*) FROM vet_reservation.reservations');
  allow('11-5', 'reservation 계정은 보호자 이름을 뷰로 읽는다', 'reservation', 'SELECT COUNT(*) FROM vet_reservation.users');
  deny('11-6', 'reservation 계정은 비밀번호 해시를 읽지 못한다', 'reservation', 'SELECT password_hash FROM vet_reservation.users LIMIT 1');
  deny('11-7', 'reservation 계정은 원본 사용자 테이블을 읽지 못한다', 'reservation', 'SELECT COUNT(*) FROM vet_auth.users');
  deny('11-8', 'reservation 계정은 진료 시각을 고치지 못한다', 'reservation', 'UPDATE vet_reservation.slots SET start_at = NOW() WHERE slot_id = 1');
  deny('11-9', 'reservation 계정은 예약을 지우지 못한다', 'reservation', 'DELETE FROM vet_reservation.reservations WHERE reservation_id = 1');
}

console.log(`\n결과: 통과 ${pass} / 실패 ${fail}`);
process.exit(Math.min(fail, 100));
