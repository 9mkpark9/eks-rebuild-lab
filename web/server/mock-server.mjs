// 로컬 확인용 모의 서버 — 의존성 없음 (node server/mock-server.mjs)
//
// 1) nginx 라우팅 흉내 (부록 E.3)
//    /health → 200 ok, /api/* → 예약 API, /app/* → dist/app (SPA, 없으면 index.html), / → dist/site
//    모든 응답에 X-Web-Node, /api 응답에 X-Served-By 를 붙인다. 노드 이름은 두 대씩 번갈아 쓴다
//    (ALB 라운드 로빈 흉내). 실제 분산 검증은 AWS에서 Locust로 한다.
// 2) WAS 예약 API 흉내 (6장)
//    메모리에 슬롯·예약을 두고, DB 판정 규칙을 그대로 따른다.
//    · 슬롯당 활성 예약 1건 (조건부 UPDATE → 0행이면 409 SLOT_TAKEN)
//    · 반려동물 1마리는 같은 날 활성 예약 1건 (uq_pet_day → 409 PET_SAME_DAY)
//    · 변경은 새 슬롯을 못 잡으면 전체 롤백, 취소된 예약은 409 CANCELLED
//    · 신청 REQUESTED → 관리자 승인 CONFIRMED (이미 취소됐으면 409 NOT_REQUESTED)
//
// 테스트 계정: 보호자 owner001~owner300, 간호사 admin1·admin2 (부록 A의 Locust와 같음), 원장 vet1~vet3.
// 공통 비밀번호는 TEST_PASSWORD. 간호사는 /api/admin/*(접수 업무), 원장은 /api/director/*(진료 업무)만 쓴다.
// 이 서버는 실제 운영에 쓰지 않는다. 운영 WAS는 Java 21 + Spring Boot 4.1 (3장, 부록 B).

process.env.TZ ??= 'Asia/Seoul';

import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PORT = Number(process.env.PORT || 8090);
const DIST = path.resolve(root, process.env.DIST || 'dist');
const LATENCY_MS = Number(process.env.LATENCY_MS ?? 120);
const TEST_PASSWORD = process.env.TEST_PASSWORD || 'test-only';
const SESSION_MIN = 30;

const config = JSON.parse(await readFile(path.join(root, 'clinic.config.json'), 'utf8'));
const TYPES = config.visitTypes.map((t) => t.code);

const WEB_NODES = ['i-0a1f3c5e7b9d24681', 'i-0b7d21e4f6a8c3579'];
const WAS_NODES = ['i-0c42e8a1d3f5b7960', 'i-0d93a5c7e1b3f5824'];
let webRR = 0;
let wasRR = 0;

/* ------------------------------------------------------------------ */
/* 날짜 도우미 (병원 현지 시각)                                         */
/* ------------------------------------------------------------------ */
const pad = (n) => String(n).padStart(2, '0');
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const isoLocal = (d) => `${ymd(d)}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const toMin = (hhmm) => { const [h, m] = hhmm.split(':').map(Number); return h * 60 + m; };
const hhmm = (min) => `${pad(Math.floor(min / 60))}:${pad(min % 60)}`;
const WEEK = ['일', '월', '화', '수', '목', '금', '토'];
const korDate = (d) => `${d.getMonth() + 1}월 ${d.getDate()}일(${WEEK[d.getDay()]})`;

// 재현 가능한 난수 (시드 고정)
function mulberry32(a) {
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = mulberry32(20261019);
const pick = (arr) => arr[Math.floor(rand() * arr.length)];

/* ------------------------------------------------------------------ */
/* 초기 데이터 (db/seed.sql 에 해당)                                    */
/* ------------------------------------------------------------------ */
const vets = new Map(config.vets.map((v) => [v.id, v]));
const users = new Map(); // userId → { userId, loginId, name, role, phone }
const usersByLogin = new Map();
const pets = new Map(); // petId → { petId, ownerId, name, species, age }
const slots = new Map(); // slotId → { slotId, vetId, startAt, date, visitType, isEvent, isOpen, reservationId }
const reservations = new Map(); // reservationId → { ... }
const notices = new Map();
let seqUser = 1, seqPet = 1, seqSlot = 1, seqResv = 1, seqNotice = 1;

function addUser(loginId, name, role, phone, vetId = null) {
  const u = { userId: seqUser++, loginId, name, role, phone, vetId };
  users.set(u.userId, u);
  usersByLogin.set(loginId, u);
  return u;
}
function addPet(ownerId, name, species, age) {
  const p = { petId: seqPet++, ownerId, name, species, age };
  pets.set(p.petId, p);
  return p;
}

const SURNAMES = ['김', '이', '박', '최', '정', '강', '조', '윤', '장', '임', '한', '오', '서', '신', '권', '황', '안', '송', '류', '홍'];
const GIVEN = ['민준', '서연', '도윤', '하은', '시우', '지우', '예준', '수아', '주원', '지민', '하준', '서윤', '지호', '채원', '준서', '다은', '현우', '유나', '건우', '소율'];
const PET_NAMES = ['콩이', '보리', '두부', '초코', '코코', '몽이', '루이', '하루', '망고', '밤이', '나비', '치즈', '레오', '쿠키', '뭉치', '호두', '구름', '별이', '토리', '모카'];

// 직원: 간호사 2명(접수 데스크, 계정 이름은 Locust와 같은 admin1·admin2), 원장 3명(수의사와 1:1)
addUser('admin1', '정하나', 'NURSE', '02-0000-0001');
addUser('admin2', '윤소미', 'NURSE', '02-0000-0002');
for (const v of config.vets) addUser(`vet${v.id}`, v.name, 'DIRECTOR', `02-0000-010${v.id}`, v.id);
for (let i = 1; i <= 300; i++) {
  const owner = addUser(`owner${String(i).padStart(3, '0')}`, pick(SURNAMES) + pick(GIVEN), 'OWNER', `010-0000-${String(1000 + i).slice(-4)}`);
  if (i === 1) {
    addPet(owner.userId, '콩이', 'DOG', 3);
    addPet(owner.userId, '나비', 'CAT', 5);
    continue;
  }
  const n = rand() < 0.4 ? 2 : 1;
  for (let k = 0; k < n; k++) addPet(owner.userId, pick(PET_NAMES), rand() < 0.62 ? 'DOG' : 'CAT', 1 + Math.floor(rand() * 14));
}

// 슬롯: 오늘부터 bookingDays일, 휴진일 제외, 30분 단위, 점심 제외
const today = new Date(); today.setHours(0, 0, 0, 0);
const H = config.hours;
const clinicDays = [];
for (let i = 0; i < config.bookingDays; i++) {
  const d = addDays(today, i);
  if (!H.closedDays.includes(d.getDay())) clinicDays.push(d);
}
// 이벤트(예방접종 할인) 3일: 오늘 이후 첫 월요일부터 진료일 3일
const firstMonday = clinicDays.findIndex((d) => d.getDay() === 1 && d > today);
const eventDays = new Set(firstMonday >= 0 ? clinicDays.slice(firstMonday, firstMonday + 3).map(ymd) : []);

const times = [];
for (let m = toMin(H.open); m < toMin(H.close); m += config.slotMinutes) {
  if (m >= toMin(H.lunchStart) && m < toMin(H.lunchEnd)) continue;
  times.push(hhmm(m));
}
for (const d of clinicDays) {
  const date = ymd(d);
  const isEvent = eventDays.has(date);
  config.vets.forEach((vet, vi) => {
    times.forEach((t, ti) => {
      const s = {
        slotId: seqSlot++, vetId: vet.id, date, startAt: `${date}T${t}:00`,
        // 평소에는 시각마다 수의사 3명이 진료 항목 3가지를 하나씩 나눠 맡는다. 이벤트 날은 전부 예방접종.
        visitType: isEvent ? 'VACCINE' : TYPES[(vi + ti) % TYPES.length],
        isEvent, isOpen: true, reservationId: null,
      };
      slots.set(s.slotId, s);
    });
  });
}

const isActive = (r) => r.status === 'REQUESTED' || r.status === 'CONFIRMED';
const petHasActiveOn = (petId, date, exceptId) =>
  [...reservations.values()].some((r) => r.petId === petId && r.visitDate === date && isActive(r) && r.reservationId !== exceptId);

function seedReservation(pet, slot, status, createdAt) {
  const r = {
    reservationId: seqResv++, ownerId: pet.ownerId, petId: pet.petId, slotId: slot.slotId,
    visitDate: slot.date, status, servedBy: WAS_NODES[seqResv % WAS_NODES.length], createdAt, // ALB 라운드 로빈처럼 번갈아
  };
  reservations.set(r.reservationId, r);
  if (isActive(r)) slot.reservationId = r.reservationId;
  return r;
}
const findSlot = (date, type, time) =>
  [...slots.values()].find((s) => s.date === date && s.visitType === type && s.startAt.slice(11, 16) === time && !s.reservationId);

// 데모 보호자(owner001)의 예약: 확정 1건, 승인 대기 1건, 취소 1건
{
  const me = usersByLogin.get('owner001');
  const [kong, nabi] = [...pets.values()].filter((p) => p.ownerId === me.userId);
  const normal = clinicDays.map(ymd).filter((d) => !eventDays.has(d) && d !== ymd(today));
  const created = isoLocal(addDays(new Date(), -2));
  const a = normal[0] && findSlot(normal[0], 'GENERAL', '10:30');
  if (a) seedReservation(kong, a, 'CONFIRMED', created);
  const b = normal[4] && findSlot(normal[4], 'CHECKUP', '15:00');
  if (b) seedReservation(nabi, b, 'REQUESTED', isoLocal(addDays(new Date(), -1)));
  const c = normal[2] && findSlot(normal[2], 'VACCINE', '11:00');
  if (c) seedReservation(kong, c, 'CANCELLED', created); // 취소된 예약은 슬롯을 잡지 않는다
}

// 다른 보호자들의 기존 예약 (평소 약 30%, 이벤트 날은 오픈 직후라 약 15%)
{
  const ownerPets = [...pets.values()].filter((p) => usersByLogin.get('owner001').userId !== p.ownerId);
  for (const s of slots.values()) {
    if (s.reservationId) continue;
    const p = rand();
    if (p > (s.isEvent ? 0.15 : 0.3)) continue;
    for (let tries = 0; tries < 5; tries++) {
      const pet = pick(ownerPets);
      if (petHasActiveOn(pet.petId, s.date)) continue;
      const status = s.isEvent ? 'REQUESTED' : rand() < 0.7 ? 'CONFIRMED' : 'REQUESTED';
      seedReservation(pet, s, status, isoLocal(addDays(new Date(), -Math.ceil(rand() * 5))));
      break;
    }
  }
}

// 공지사항
function addNotice(category, title, content, pinned, daysAgo) {
  const n = {
    noticeId: seqNotice++, category, title, content, pinned,
    createdAt: isoLocal(addDays(new Date(new Date().setHours(10, 0, 0, 0)), -daysAgo)),
  };
  notices.set(n.noticeId, n);
}
{
  const ev = [...eventDays].sort();
  const evStart = ev.length ? new Date(`${ev[0]}T00:00:00`) : null;
  const evEnd = ev.length ? new Date(`${ev[ev.length - 1]}T00:00:00`) : null;
  addNotice('NOTICE', '온라인 진료 예약 서비스를 시작합니다',
    `이제 전화하지 않아도 진료 예약을 할 수 있습니다.\n\n· 예약 가능 기간: 오늘부터 14일\n· 진료 항목: 일반 진료, 예방접종, 건강검진 (각 30분)\n· 신청한 시간은 바로 잡히며, 병원에서 확인한 뒤 ‘예약 확정’으로 바뀝니다.\n· 변경·취소는 ‘내 예약’에서 직접 할 수 있습니다.\n\n계정이 없으신 보호자님은 방문 시 접수처에 말씀해 주세요.`,
    false, 21);
  addNotice('NOTICE', '고양이 전용 대기 공간 안내',
    `고양이 보호자님은 접수 후 오른쪽 ‘고양이 대기 공간’에서 기다려 주세요.\n강아지와 동선을 분리해 아이들이 덜 긴장하도록 준비했습니다.`, false, 14);
  addNotice('CLOSED', '공휴일 휴진 안내',
    `공휴일에는 휴진합니다. 온라인 예약은 공휴일에도 신청할 수 있으며, 다음 진료일에 순서대로 확인해 드립니다.\n응급 상황에는 가까운 24시 응급 동물병원을 이용해 주세요.`, false, 9);
  addNotice('NOTICE', '주차 안내 (건물 뒤편 전용 주차장)',
    `${config.parking}\n주차 공간이 부족할 때는 인근 공영주차장을 이용해 주세요.`, false, 5);
  if (evStart) {
    addNotice('EVENT', `예방접종 할인 예약 오픈 — ${korDate(evStart)} 09:00`,
      `${korDate(evStart)}부터 ${korDate(evEnd)}까지 3일간 예방접종을 할인된 가격으로 진행합니다.\n\n· 대상: 강아지·고양이 종합백신, 광견병, 심장사상충 예방\n· 예약: 온라인 예약 → 진료 항목 ‘예방접종’ → 할인 기간 날짜 선택\n· 할인 기간에는 수의사 3명 모두 예방접종만 진료합니다.\n\n예약이 몰리면 같은 시간을 여러 보호자님이 동시에 신청할 수 있습니다. 먼저 처리된 한 건만 예약되며, ‘이미 예약된 시간’ 안내를 받으시면 다른 시간을 선택해 주세요.`,
      true, 1);
  }
}

/* ------------------------------------------------------------------ */
/* 세션 (운영: Spring Session + ElastiCache)                            */
/* ------------------------------------------------------------------ */
const sessions = new Map(); // sid → { userId, expires }
const loginFails = new Map(); // loginId → { count, until }

function parseCookies(req) {
  const out = {};
  (req.headers.cookie || '').split(';').forEach((c) => {
    const i = c.indexOf('=');
    if (i > 0) out[c.slice(0, i).trim()] = decodeURIComponent(c.slice(i + 1).trim());
  });
  return out;
}
function currentUser(req) {
  const sid = parseCookies(req).SESSION;
  const s = sid && sessions.get(sid);
  if (!s) return null;
  if (s.expires < Date.now()) { sessions.delete(sid); return null; }
  s.expires = Date.now() + SESSION_MIN * 60_000; // 요청마다 연장
  return users.get(s.userId);
}
const userView = (u) => ({ userId: u.userId, loginId: u.loginId, name: u.name, role: u.role, vetId: u.vetId });

/* ------------------------------------------------------------------ */
/* 응답 도우미                                                          */
/* ------------------------------------------------------------------ */
class HttpError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
const MESSAGES = {
  UNAUTHORIZED: '로그인이 필요합니다.',
  FORBIDDEN: '권한이 없습니다.',
  NOT_FOUND: '요청한 정보를 찾을 수 없습니다.',
  SLOT_TAKEN: '이미 예약된 시간입니다.',
  PET_SAME_DAY: '같은 반려동물은 같은 날 한 건만 예약할 수 있습니다.',
  CANCELLED: '이미 취소된 예약입니다.',
  NOT_REQUESTED: '승인 대기 상태가 아닙니다.',
  INVALID_CREDENTIALS: '아이디 또는 비밀번호가 올바르지 않습니다.',
  TOO_MANY_ATTEMPTS: '로그인 시도가 너무 많습니다. 잠시 후 다시 시도해 주세요.',
};
const fail = (status, code, message) => { throw new HttpError(status, code, message || MESSAGES[code] || code); };

function sendJson(res, status, body, headers = {}) {
  const data = body === undefined ? '' : JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...headers });
  res.end(res.req.method === 'HEAD' ? undefined : data);
}
async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const c of req) { size += c.length; if (size > 64 * 1024) fail(413, 'TOO_LARGE', '요청이 너무 큽니다.'); chunks.push(c); }
  if (!chunks.length) return {};
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { fail(400, 'INVALID', 'JSON 형식이 올바르지 않습니다.'); }
}
const requireUser = (req) => currentUser(req) || fail(401, 'UNAUTHORIZED');
function requireRole(req, role) {
  const u = requireUser(req);
  if (u.role !== role) fail(403, 'FORBIDDEN');
  return u;
}
const intParam = (v) => { const n = Number(v); if (!Number.isInteger(n) || n <= 0) fail(404, 'NOT_FOUND'); return n; };
const validDate = (s) => /^\d{4}-\d{2}-\d{2}$/.test(s || '');

function resvView(r) {
  const s = slots.get(r.slotId);
  const pet = pets.get(r.petId);
  const vet = vets.get(s.vetId);
  return {
    reservationId: r.reservationId, petId: r.petId, petName: pet.name, petSpecies: pet.species,
    slotId: r.slotId, startAt: s.startAt, visitDate: r.visitDate, visitType: s.visitType,
    vetId: vet.id, vetName: vet.name, vetTitle: vet.title, isEvent: s.isEvent,
    status: r.status, servedBy: r.servedBy, createdAt: r.createdAt,
  };
}
function slotView(s) {
  const vet = vets.get(s.vetId);
  return { slotId: s.slotId, vetId: s.vetId, vetName: vet.name, vetTitle: vet.title, startAt: s.startAt, visitType: s.visitType, isEvent: s.isEvent };
}
function noticeView(n, withContent) {
  const v = { noticeId: n.noticeId, category: n.category, title: n.title, pinned: n.pinned, createdAt: n.createdAt };
  if (withContent) v.content = n.content;
  return v;
}
function validatePet(body) {
  const name = String(body.name ?? '').trim();
  const age = Number(body.age);
  if (!name || name.length > 20) fail(400, 'INVALID', '이름은 1~20자로 입력해 주세요.');
  if (!['DOG', 'CAT', 'ETC'].includes(body.species)) fail(400, 'INVALID', '종류를 선택해 주세요.');
  if (!Number.isInteger(age) || age < 0 || age > 40) fail(400, 'INVALID', '나이는 0~40 사이 숫자로 입력해 주세요.');
  return { name, species: body.species, age };
}
function lockMine(owner, id) {
  const r = reservations.get(id);
  if (!r || r.ownerId !== owner.userId) fail(404, 'NOT_FOUND'); // 남의 예약이 있다는 사실도 드러내지 않는다
  if (r.status === 'CANCELLED') fail(409, 'CANCELLED');
  return r;
}
function openSlot(id) {
  const s = slots.get(Number(id));
  if (!s || !s.isOpen) fail(404, 'NOT_FOUND', '예약할 수 없는 시간입니다.');
  return s;
}

/* ------------------------------------------------------------------ */
/* API 라우터                                                           */
/* ------------------------------------------------------------------ */
const routes = [];
const route = (method, pattern, handler) => {
  const keys = [];
  const re = new RegExp('^' + pattern.replace(/:(\w+)/g, (_, k) => { keys.push(k); return '([^/]+)'; }) + '/?$');
  routes.push({ method, re, keys, handler });
};

// 인증
route('POST', '/api/auth/login', async (ctx) => {
  const { loginId = '', password = '' } = await readBody(ctx.req);
  // 계정별 실패 5회면 1분간 429 (운영: ElastiCache 카운터, 6장)
  const f = loginFails.get(loginId) ?? { count: 0, until: 0 };
  if (f.until > Date.now()) fail(429, 'TOO_MANY_ATTEMPTS');
  const u = usersByLogin.get(String(loginId));
  if (!u || password !== TEST_PASSWORD) {
    f.count += 1;
    if (f.count >= 5) { f.until = Date.now() + 60_000; f.count = 0; }
    loginFails.set(loginId, f);
    fail(401, 'INVALID_CREDENTIALS');
  }
  loginFails.delete(loginId);
  const sid = crypto.randomBytes(24).toString('base64url');
  sessions.set(sid, { userId: u.userId, expires: Date.now() + SESSION_MIN * 60_000 });
  sendJson(ctx.res, 200, userView(u), { 'Set-Cookie': `SESSION=${sid}; Path=/; HttpOnly; SameSite=Lax` });
});
route('POST', '/api/auth/logout', async (ctx) => {
  const sid = parseCookies(ctx.req).SESSION;
  if (sid) sessions.delete(sid);
  sendJson(ctx.res, 204, undefined, { 'Set-Cookie': 'SESSION=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0' });
});
route('GET', '/api/auth/me', async (ctx) => sendJson(ctx.res, 200, userView(requireUser(ctx.req))));

// 공지
route('GET', '/api/notices', async (ctx) => {
  const list = [...notices.values()].sort((a, b) => b.createdAt.localeCompare(a.createdAt)).map((n) => noticeView(n));
  sendJson(ctx.res, 200, list);
});
route('GET', '/api/notices/:id', async (ctx) => {
  const n = notices.get(intParam(ctx.params.id)) || fail(404, 'NOT_FOUND', '공지사항을 찾을 수 없습니다.');
  sendJson(ctx.res, 200, noticeView(n, true));
});

// 반려동물
route('GET', '/api/pets', async (ctx) => {
  const u = requireRole(ctx.req, 'OWNER');
  sendJson(ctx.res, 200, [...pets.values()].filter((p) => p.ownerId === u.userId).map(({ ownerId, ...p }) => p));
});
route('POST', '/api/pets', async (ctx) => {
  const u = requireRole(ctx.req, 'OWNER');
  const v = validatePet(await readBody(ctx.req));
  const { ownerId, ...p } = addPet(u.userId, v.name, v.species, v.age);
  sendJson(ctx.res, 201, p);
});
route('PUT', '/api/pets/:id', async (ctx) => {
  const u = requireRole(ctx.req, 'OWNER');
  const p = pets.get(intParam(ctx.params.id));
  if (!p || p.ownerId !== u.userId) fail(404, 'NOT_FOUND');
  Object.assign(p, validatePet(await readBody(ctx.req)));
  const { ownerId, ...view } = p;
  sendJson(ctx.res, 200, view);
});

// 예약 가능 시간 (비어 있고, 열려 있고, 지금 이후인 슬롯만)
route('GET', '/api/slots', async (ctx) => {
  const date = ctx.url.searchParams.get('date');
  const type = ctx.url.searchParams.get('type');
  if (!validDate(date)) fail(400, 'INVALID', 'date는 YYYY-MM-DD 형식이어야 합니다.');
  if (type && !TYPES.includes(type)) fail(400, 'INVALID', '알 수 없는 진료 항목입니다.');
  const now = isoLocal(new Date());
  const list = [...slots.values()]
    .filter((s) => s.date === date && (!type || s.visitType === type) && s.isOpen && !s.reservationId && s.startAt > now)
    .sort((a, b) => a.startAt.localeCompare(b.startAt) || a.vetId - b.vetId)
    .map(slotView);
  sendJson(ctx.res, 200, list);
});

// 예약
route('POST', '/api/reservations', async (ctx) => {
  const u = requireRole(ctx.req, 'OWNER');
  const { petId, slotId } = await readBody(ctx.req);
  const pet = pets.get(Number(petId));
  if (!pet || pet.ownerId !== u.userId) fail(404, 'NOT_FOUND', '반려동물 정보를 찾을 수 없습니다.');
  const s = openSlot(slotId);
  if (petHasActiveOn(pet.petId, s.date)) fail(409, 'PET_SAME_DAY'); // ① INSERT 의 uq_pet_day
  if (s.reservationId) fail(409, 'SLOT_TAKEN'); // ② 조건부 UPDATE 가 0행
  const r = {
    reservationId: seqResv++, ownerId: u.userId, petId: pet.petId, slotId: s.slotId,
    visitDate: s.date, status: 'REQUESTED', servedBy: ctx.node, createdAt: isoLocal(new Date()),
  };
  reservations.set(r.reservationId, r);
  s.reservationId = r.reservationId;
  sendJson(ctx.res, 201, resvView(r));
});
route('GET', '/api/reservations/me', async (ctx) => {
  const u = requireRole(ctx.req, 'OWNER');
  const list = [...reservations.values()].filter((r) => r.ownerId === u.userId).map(resvView)
    .sort((a, b) => a.startAt.localeCompare(b.startAt));
  sendJson(ctx.res, 200, list);
});
route('PUT', '/api/reservations/:id', async (ctx) => {
  const u = requireRole(ctx.req, 'OWNER');
  const r = lockMine(u, intParam(ctx.params.id));
  const { slotId } = await readBody(ctx.req);
  if (Number(slotId) === r.slotId) return sendJson(ctx.res, 200, resvView(r));
  const next = openSlot(slotId);
  // 기존 슬롯 비우기 → 새 슬롯 조건부 확보 → 예약 행 갱신. 어느 단계든 실패하면 전체 롤백(아무것도 바꾸지 않음)
  if (next.reservationId) fail(409, 'SLOT_TAKEN');
  if (petHasActiveOn(r.petId, next.date, r.reservationId)) fail(409, 'PET_SAME_DAY');
  const prev = slots.get(r.slotId);
  if (prev.reservationId === r.reservationId) prev.reservationId = null;
  next.reservationId = r.reservationId;
  Object.assign(r, { slotId: next.slotId, visitDate: next.date, status: 'REQUESTED' });
  sendJson(ctx.res, 200, resvView(r));
});
route('DELETE', '/api/reservations/:id', async (ctx) => {
  const u = requireRole(ctx.req, 'OWNER');
  const r = lockMine(u, intParam(ctx.params.id));
  const s = slots.get(r.slotId);
  if (s.reservationId === r.reservationId) s.reservationId = null;
  r.status = 'CANCELLED';
  sendJson(ctx.res, 204);
});

// 간호사 (접수 데스크) — 경로는 부록 A의 Locust AdminUser 와 맞추려고 /api/admin 을 그대로 쓴다
route('GET', '/api/admin/reservations', async (ctx) => {
  requireRole(ctx.req, 'NURSE');
  const date = ctx.url.searchParams.get('date');
  if (!validDate(date)) fail(400, 'INVALID', 'date는 YYYY-MM-DD 형식이어야 합니다.');
  const list = [...reservations.values()].filter((r) => r.visitDate === date).map((r) => {
    const owner = users.get(r.ownerId);
    return { ...resvView(r), ownerName: owner.name, ownerLoginId: owner.loginId, ownerPhone: owner.phone };
  }).sort((a, b) => a.startAt.localeCompare(b.startAt) || a.vetId - b.vetId);
  sendJson(ctx.res, 200, list);
});
route('POST', '/api/admin/reservations/:id/approve', async (ctx) => {
  requireRole(ctx.req, 'NURSE');
  const r = reservations.get(intParam(ctx.params.id)) || fail(404, 'NOT_FOUND');
  if (r.status !== 'REQUESTED') fail(409, 'NOT_REQUESTED');
  r.status = 'CONFIRMED';
  sendJson(ctx.res, 200, resvView(r));
});
// 간호사는 남은 시간을 보고 전화 예약을 안내하므로 슬롯은 조회만 한다 (열기·닫기는 원장)
route('GET', '/api/admin/slots', async (ctx) => {
  requireRole(ctx.req, 'NURSE');
  const date = ctx.url.searchParams.get('date');
  if (!validDate(date)) fail(400, 'INVALID', 'date는 YYYY-MM-DD 형식이어야 합니다.');
  const list = [...slots.values()].filter((s) => s.date === date)
    .sort((a, b) => a.startAt.localeCompare(b.startAt) || a.vetId - b.vetId)
    .map((s) => {
      const r = s.reservationId && reservations.get(s.reservationId);
      return { ...slotView(s), isOpen: s.isOpen, reservationId: s.reservationId, petName: r ? pets.get(r.petId).name : null, status: r ? r.status : null };
    });
  sendJson(ctx.res, 200, list);
});
route('POST', '/api/admin/notices', async (ctx) => {
  requireRole(ctx.req, 'NURSE');
  const body = await readBody(ctx.req);
  const title = String(body.title ?? '').trim();
  const content = String(body.content ?? '').trim();
  if (!title || title.length > 100) fail(400, 'INVALID', '제목은 1~100자로 입력해 주세요.');
  if (!content) fail(400, 'INVALID', '내용을 입력해 주세요.');
  const category = ['NOTICE', 'EVENT', 'CLOSED'].includes(body.category) ? body.category : 'NOTICE';
  const n = { noticeId: seqNotice++, category, title, content, pinned: !!body.pinned, createdAt: isoLocal(new Date()) };
  notices.set(n.noticeId, n);
  sendJson(ctx.res, 201, noticeView(n, true));
});
route('DELETE', '/api/admin/notices/:id', async (ctx) => {
  requireRole(ctx.req, 'NURSE');
  if (!notices.delete(intParam(ctx.params.id))) fail(404, 'NOT_FOUND');
  sendJson(ctx.res, 204);
});

// 원장 (수의사) — 계정마다 vetId 가 연결되어 있어 본인 진료만 보고 바꾼다
route('GET', '/api/director/schedule', async (ctx) => {
  const u = requireRole(ctx.req, 'DIRECTOR');
  const date = ctx.url.searchParams.get('date');
  if (!validDate(date)) fail(400, 'INVALID', 'date는 YYYY-MM-DD 형식이어야 합니다.');
  const list = [...slots.values()].filter((s) => s.date === date && s.vetId === u.vetId)
    .sort((a, b) => a.startAt.localeCompare(b.startAt))
    .map((s) => {
      const r = s.reservationId && reservations.get(s.reservationId);
      const pet = r && pets.get(r.petId);
      const owner = r && users.get(r.ownerId);
      return {
        slotId: s.slotId, startAt: s.startAt, visitType: s.visitType, isEvent: s.isEvent, isOpen: s.isOpen,
        reservation: r ? {
          reservationId: r.reservationId, status: r.status, petId: pet.petId, petName: pet.name, petSpecies: pet.species,
          petAge: pet.age, ownerName: owner.name, ownerPhone: owner.phone, createdAt: r.createdAt,
        } : null,
      };
    });
  sendJson(ctx.res, 200, list);
});
route('PUT', '/api/director/slots/:id', async (ctx) => {
  const u = requireRole(ctx.req, 'DIRECTOR');
  const s = slots.get(intParam(ctx.params.id)) || fail(404, 'NOT_FOUND');
  if (s.vetId !== u.vetId) fail(403, 'FORBIDDEN', '본인 진료 시간만 바꿀 수 있습니다.');
  const { isOpen } = await readBody(ctx.req);
  if (typeof isOpen !== 'boolean') fail(400, 'INVALID', 'isOpen 값이 필요합니다.');
  s.isOpen = isOpen; // 닫아도 이미 잡힌 예약은 그대로 둔다 (새 예약만 막는다)
  sendJson(ctx.res, 200, { slotId: s.slotId, startAt: s.startAt, visitType: s.visitType, isEvent: s.isEvent, isOpen: s.isOpen });
});
// 병원 현황: 예약 가능 기간(14일) 전체 집계
route('GET', '/api/director/stats', async (ctx) => {
  requireRole(ctx.req, 'DIRECTOR');
  const now = isoLocal(new Date());
  const all = [...reservations.values()];
  const slotOf = (r) => slots.get(r.slotId);
  const count = (list, status) => list.filter((r) => r.status === status).length;
  const days = clinicDays.map(ymd).map((date) => {
    const daySlots = [...slots.values()].filter((s) => s.date === date);
    const dayResv = all.filter((r) => r.visitDate === date);
    return {
      date, isEvent: eventDays.has(date), slots: daySlots.length, closed: daySlots.filter((s) => !s.isOpen).length,
      confirmed: count(dayResv, 'CONFIRMED'), requested: count(dayResv, 'REQUESTED'), cancelled: count(dayResv, 'CANCELLED'),
    };
  });
  const active = all.filter(isActive);
  sendJson(ctx.res, 200, {
    days,
    byVet: config.vets.map((v) => ({
      vetId: v.id, vetName: v.name, vetTitle: v.title,
      active: active.filter((r) => slotOf(r).vetId === v.id).length,
      slots: [...slots.values()].filter((s) => s.vetId === v.id).length,
    })),
    byType: TYPES.map((t) => ({ visitType: t, active: active.filter((r) => slotOf(r).visitType === t).length })),
    byWas: WAS_NODES.map((n) => ({ servedBy: n, count: all.filter((r) => r.servedBy === n).length })),
    totals: {
      slots: slots.size,
      active: active.length,
      confirmed: count(all, 'CONFIRMED'),
      requested: count(all, 'REQUESTED'),
      cancelled: count(all, 'CANCELLED'),
      closed: [...slots.values()].filter((s) => !s.isOpen).length,
      open: [...slots.values()].filter((s) => s.isOpen && !s.reservationId && s.startAt > now).length,
    },
  });
});

async function handleApi(req, res, url, node) {
  const method = req.method === 'HEAD' ? 'GET' : req.method;
  for (const r of routes) {
    const m = url.pathname.match(r.re);
    if (!m) continue;
    if (r.method !== method) continue;
    const params = Object.fromEntries(r.keys.map((k, i) => [k, decodeURIComponent(m[i + 1])]));
    return r.handler({ req, res, url, params, node });
  }
  fail(404, 'NOT_FOUND', '없는 API입니다.');
}

/* ------------------------------------------------------------------ */
/* 정적 파일 (nginx location / 와 /app/)                                 */
/* ------------------------------------------------------------------ */
const MIME = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.ico': 'image/x-icon', '.woff2': 'font/woff2', '.txt': 'text/plain; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
};
async function fileIfExists(base, rel) {
  const full = path.resolve(base, '.' + rel);
  if (full !== base && !full.startsWith(base + path.sep)) return null; // 경로 탈출 방지
  try { const s = await stat(full); return s.isFile() ? full : null; } catch { return null; }
}
async function sendFile(res, file, status = 200) {
  const ext = path.extname(file).toLowerCase();
  const body = await readFile(file);
  const cache = file.includes(`${path.sep}app${path.sep}assets${path.sep}`) ? 'public, max-age=31536000, immutable' : 'no-cache';
  res.writeHead(status, { 'Content-Type': MIME[ext] || 'application/octet-stream', 'Cache-Control': cache });
  res.end(res.req.method === 'HEAD' ? undefined : body);
}
function sendText(res, status, text) {
  res.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end(res.req.method === 'HEAD' ? undefined : text);
}

async function handleStatic(req, res, pathname) {
  if (req.method !== 'GET' && req.method !== 'HEAD') return sendText(res, 405, 'Method Not Allowed');
  if (pathname.startsWith('/app/')) {
    // location /app/ { try_files $uri /app/index.html; }
    const f = await fileIfExists(DIST, pathname);
    if (f) return sendFile(res, f);
    const index = await fileIfExists(DIST, '/app/index.html');
    if (index) return sendFile(res, index);
    return sendText(res, 503, '예약 화면이 아직 빌드되지 않았습니다. web 폴더에서 npm run build 를 실행하세요.');
  }
  // location / { root site; try_files $uri $uri.html $uri/ =404; }
  const siteDir = path.join(DIST, 'site');
  const f = (await fileIfExists(siteDir, pathname))
    || (await fileIfExists(siteDir, pathname + '.html'))
    || (await fileIfExists(siteDir, path.posix.join(pathname, 'index.html')));
  if (f) return sendFile(res, f);
  return sendText(res, 404, '404 Not Found');
}

/* ------------------------------------------------------------------ */
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  res.setHeader('X-Web-Node', WEB_NODES[webRR++ % WEB_NODES.length]);
  try {
    if (url.pathname === '/health') return sendText(res, 200, 'ok');
    if (url.pathname.startsWith('/api/')) {
      const node = WAS_NODES[wasRR++ % WAS_NODES.length];
      res.setHeader('X-Served-By', node);
      if (LATENCY_MS > 0) await new Promise((r) => setTimeout(r, LATENCY_MS * (0.5 + rand())));
      return await handleApi(req, res, url, node);
    }
    if (url.pathname === '/app') { res.writeHead(301, { Location: '/app/' }); return res.end(); }
    return await handleStatic(req, res, decodeURIComponent(url.pathname));
  } catch (e) {
    if (e instanceof HttpError) return sendJson(res, e.status, { code: e.code, message: e.message });
    console.error(e);
    if (!res.headersSent) sendJson(res, 500, { code: 'INTERNAL', message: '서버 오류가 발생했습니다.' });
  }
});

server.listen(PORT, () => {
  const filled = [...slots.values()].filter((s) => s.reservationId).length;
  console.log(`[mock] http://localhost:${PORT}  (site · /app/ · /api)  dist=${path.relative(root, DIST) || '.'}`);
  console.log(`[mock] 슬롯 ${slots.size}개 (예약 ${filled}건), 이벤트 날 ${[...eventDays].join(', ') || '없음'}, 보호자 300명 · 간호사 2명 · 원장 3명`);
});
