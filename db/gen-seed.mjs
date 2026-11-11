// 초기 데이터 생성: node db/gen-seed.mjs > db/seed.sql
// 오늘부터 14일의 슬롯(576개 안팎), 테스트 보호자 300명(반려동물 1~2마리), 간호사 2명, 원장 3명, 공지.
// 계정은 부록 A의 Locust와 같다: owner001~owner300, admin1·admin2(간호사), vet1~vet3(원장).
// 비밀번호는 모두 테스트용 공통값이며 여기에는 BCrypt 해시만 둔다. 실제 개인정보는 넣지 않는다(11장).
process.env.TZ = 'Asia/Seoul';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const clinic = JSON.parse(readFileSync(path.join(root, 'web', 'clinic.config.json'), 'utf8'));
const PASSWORD_HASH = '$2a$10$2rN1itCWrmsUN1WWfim4suCshXv3yOz0mBW9MhPCLhMD6U.T0lfXW'; // BCrypt(강도 10)

const pad = (n) => String(n).padStart(2, '0');
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const dt = (d) => `${ymd(d)} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const q = (s) => (s == null ? 'NULL' : `'${String(s).replace(/\\/g, '\\\\').replace(/'/g, "''")}'`);
const WEEK = ['일', '월', '화', '수', '목', '금', '토'];
const korDate = (d) => `${d.getMonth() + 1}월 ${d.getDate()}일(${WEEK[d.getDay()]})`;

// 재현 가능한 난수 (모의 서버와 같은 시드)
let seed = 20261019;
const rand = () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const pick = (a) => a[Math.floor(rand() * a.length)];

const out = [];
const emit = (s) => out.push(s);
function insert(table, cols, rows) {
  for (let i = 0; i < rows.length; i += 500) {
    emit(`INSERT INTO ${table} (${cols.join(', ')}) VALUES\n${rows.slice(i, i + 500).map((r) => `(${r.join(', ')})`).join(',\n')};`);
  }
}

emit('-- 생성: ' + new Date().toISOString() + ' (db/gen-seed.mjs)');
emit('SET NAMES utf8mb4;');

// 수의사
insert('vets', ['vet_id', 'name', 'title', 'field'], clinic.vets.map((v) => [v.id, q(v.name), q(v.title), q(v.field)]));

// 사용자
const users = [];
let uid = 0;
const addUser = (loginId, name, role, phone, vetId = null) => { users.push({ id: ++uid, loginId, name, role, phone, vetId }); return uid; };
addUser('admin1', '정하나', 'NURSE', '02-0000-0001');
addUser('admin2', '윤소미', 'NURSE', '02-0000-0002');
for (const v of clinic.vets) addUser(`vet${v.id}`, v.name, 'DIRECTOR', `02-0000-010${v.id}`, v.id);
const SURNAMES = ['김', '이', '박', '최', '정', '강', '조', '윤', '장', '임', '한', '오', '서', '신', '권', '황', '안', '송', '류', '홍'];
const GIVEN = ['민준', '서연', '도윤', '하은', '시우', '지우', '예준', '수아', '주원', '지민', '하준', '서윤', '지호', '채원', '준서', '다은', '현우', '유나', '건우', '소율'];
const PET_NAMES = ['콩이', '보리', '두부', '초코', '코코', '몽이', '루이', '하루', '망고', '밤이', '나비', '치즈', '레오', '쿠키', '뭉치', '호두', '구름', '별이', '토리', '모카'];
const pets = [];
let pid = 0;
let demoOwner = 0;
for (let i = 1; i <= 300; i++) {
  const id = addUser(`owner${String(i).padStart(3, '0')}`, pick(SURNAMES) + pick(GIVEN), 'OWNER', `010-0000-${String(1000 + i).slice(-4)}`);
  if (i === 1) {
    demoOwner = id;
    pets.push({ id: ++pid, owner: id, name: '콩이', species: 'DOG', age: 3 });
    pets.push({ id: ++pid, owner: id, name: '나비', species: 'CAT', age: 5 });
    continue;
  }
  const n = rand() < 0.4 ? 2 : 1;
  for (let k = 0; k < n; k++) pets.push({ id: ++pid, owner: id, name: pick(PET_NAMES), species: rand() < 0.62 ? 'DOG' : 'CAT', age: 1 + Math.floor(rand() * 14) });
}
insert('users', ['user_id', 'login_id', 'password_hash', 'name', 'role', 'phone', 'vet_id'],
  users.map((u) => [u.id, q(u.loginId), q(PASSWORD_HASH), q(u.name), q(u.role), q(u.phone), u.vetId ?? 'NULL']));
insert('pets', ['pet_id', 'owner_id', 'name', 'species', 'age'], pets.map((p) => [p.id, p.owner, q(p.name), q(p.species), p.age]));

// 슬롯: 오늘부터 14일, 일요일 휴진, 30분, 점심 제외. 이벤트(예방접종 할인) 3일 = 오늘 이후 첫 월요일부터 진료일 3일
const today = new Date(); today.setHours(0, 0, 0, 0);
const clinicDays = [];
for (let i = 0; i < clinic.bookingDays; i++) { const d = addDays(today, i); if (!clinic.hours.closedDays.includes(d.getDay())) clinicDays.push(d); }
const firstMonday = clinicDays.findIndex((d) => d.getDay() === 1 && d > today);
const eventDays = new Set(firstMonday >= 0 ? clinicDays.slice(firstMonday, firstMonday + 3).map(ymd) : []);
const toMin = (s) => { const [h, m] = s.split(':').map(Number); return h * 60 + m; };
const times = [];
for (let m = toMin(clinic.hours.open); m < toMin(clinic.hours.close); m += clinic.slotMinutes) {
  if (m >= toMin(clinic.hours.lunchStart) && m < toMin(clinic.hours.lunchEnd)) continue;
  times.push(`${pad(Math.floor(m / 60))}:${pad(m % 60)}:00`);
}
const TYPES = ['GENERAL', 'VACCINE', 'CHECKUP'];
const slots = [];
let sid = 0;
for (const d of clinicDays) {
  const date = ymd(d);
  const isEvent = eventDays.has(date);
  clinic.vets.forEach((v, vi) => times.forEach((t, ti) => slots.push({
    id: ++sid, vet: v.id, date, startAt: `${date} ${t}`, type: isEvent ? 'VACCINE' : TYPES[(vi + ti) % 3], isEvent, resv: null,
  })));
}

// 예약: 데모 보호자(owner001) 3건 + 다른 보호자들 (평소 약 30%, 이벤트 날 약 15%)
const resvs = [];
let rid = 0;
const petDay = new Set();
function book(pet, slot, status, created) {
  const r = { id: ++rid, owner: pet.owner, pet: pet.id, slot: slot.id, date: slot.date, status, created };
  resvs.push(r);
  if (status !== 'CANCELLED') { slot.resv = r.id; petDay.add(`${pet.id}|${slot.date}`); }
}
const findSlot = (date, type, time) => slots.find((s) => s.date === date && s.type === type && s.startAt.endsWith(time) && !s.resv);
{
  const [kong, nabi] = pets.filter((p) => p.owner === demoOwner);
  const normal = clinicDays.map(ymd).filter((d) => !eventDays.has(d) && d !== ymd(today));
  const c2 = dt(addDays(new Date(), -2)), c1 = dt(addDays(new Date(), -1));
  const a = normal[0] && findSlot(normal[0], 'GENERAL', '10:30:00'); if (a) book(kong, a, 'CONFIRMED', c2);
  const b = normal[4] && findSlot(normal[4], 'CHECKUP', '15:00:00'); if (b) book(nabi, b, 'REQUESTED', c1);
  const c = normal[2] && findSlot(normal[2], 'VACCINE', '11:00:00'); if (c) book(kong, c, 'CANCELLED', c2);
}
const others = pets.filter((p) => p.owner !== demoOwner);
for (const s of slots) {
  if (s.resv || rand() > (s.isEvent ? 0.15 : 0.3)) continue;
  for (let tries = 0; tries < 5; tries++) {
    const pet = pick(others);
    if (petDay.has(`${pet.id}|${s.date}`)) continue;
    book(pet, s, s.isEvent ? 'REQUESTED' : rand() < 0.7 ? 'CONFIRMED' : 'REQUESTED', dt(addDays(new Date(), -Math.ceil(rand() * 5))));
    break;
  }
}
// 시드 예약은 served_by = 'seed' (실제 WAS 가 처리한 예약과 구분 — 병원 현황의 WAS 분산 집계에서 빠진다)
insert('reservations', ['reservation_id', 'owner_id', 'pet_id', 'slot_id', 'visit_date', 'status', 'served_by', 'created_at'],
  resvs.map((r) => [r.id, r.owner, r.pet, r.slot, q(r.date), q(r.status), q('seed'), q(r.created)]));
insert('slots', ['slot_id', 'vet_id', 'start_at', 'visit_type', 'is_event', 'is_open', 'reservation_id'],
  slots.map((s) => [s.id, s.vet, q(s.startAt), q(s.type), s.isEvent ? 1 : 0, 1, s.resv ?? 'NULL']));

// 공지
const at10 = (daysAgo) => { const d = addDays(today, -daysAgo); d.setHours(10, 0, 0, 0); return dt(d); };
const notices = [
  ['NOTICE', '온라인 진료 예약 서비스를 시작합니다', '이제 전화하지 않아도 진료 예약을 할 수 있습니다.\n\n· 예약 가능 기간: 오늘부터 14일\n· 진료 항목: 일반 진료, 예방접종, 건강검진 (각 30분)\n· 신청한 시간은 바로 잡히며, 병원에서 확인한 뒤 ‘예약 확정’으로 바뀝니다.\n· 변경·취소는 ‘내 예약’에서 직접 할 수 있습니다.\n\n계정이 없으신 보호자님은 방문 시 접수처에 말씀해 주세요.', 0, 21],
  ['NOTICE', '고양이 전용 대기 공간 안내', '고양이 보호자님은 접수 후 오른쪽 ‘고양이 대기 공간’에서 기다려 주세요.\n강아지와 동선을 분리해 아이들이 덜 긴장하도록 준비했습니다.', 0, 14],
  ['CLOSED', '공휴일 휴진 안내', '공휴일에는 휴진합니다. 온라인 예약은 공휴일에도 신청할 수 있으며, 다음 진료일에 순서대로 확인해 드립니다.\n응급 상황에는 가까운 24시 응급 동물병원을 이용해 주세요.', 0, 9],
  ['NOTICE', '주차 안내 (건물 뒤편 전용 주차장)', `${clinic.parking}\n주차 공간이 부족할 때는 인근 공영주차장을 이용해 주세요.`, 0, 5],
];
const ev = [...eventDays].sort();
if (ev.length) {
  const s = new Date(`${ev[0]}T00:00:00`), e = new Date(`${ev[ev.length - 1]}T00:00:00`);
  notices.push(['EVENT', `예방접종 할인 예약 오픈 — ${korDate(s)} 09:00`,
    `${korDate(s)}부터 ${korDate(e)}까지 3일간 예방접종을 할인된 가격으로 진행합니다.\n\n· 대상: 강아지·고양이 종합백신, 광견병, 심장사상충 예방\n· 예약: 온라인 예약 → 진료 항목 ‘예방접종’ → 할인 기간 날짜 선택\n· 할인 기간에는 수의사 3명 모두 예방접종만 진료합니다.\n\n예약이 몰리면 같은 시간을 여러 보호자님이 동시에 신청할 수 있습니다. 먼저 처리된 한 건만 예약되며, ‘이미 예약된 시간’ 안내를 받으시면 다른 시간을 선택해 주세요.`, 1, 1]);
}
insert('notices', ['category', 'title', 'content', 'pinned', 'created_at'], notices.map(([c, t, body, p, ago]) => [q(c), q(t), q(body), p, q(at10(ago))]));

emit(`-- 슬롯 ${slots.length}개, 예약 ${resvs.length}건, 사용자 ${users.length}명, 반려동물 ${pets.length}마리, 이벤트 날 ${ev.join(', ') || '없음'}`);
process.stdout.write(out.join('\n') + '\n');
