// 동시 신청 반복 — 보호자 10명이 같은 시간을 동시에 신청하는 것을 여러 번 되풀이하고, 정상(201 한 건 + 409 아홉 건)이 아닌 회차를 출력한다.
// ② 문서의 문제 C-11 을 조사할 때 썼다.
//   PC 에서:        node v2/tests/race-repeat.mjs http://127.0.0.1:28080 40
//   네트워크 안에서: docker run --rm -i --network v2_default node:22-alpine node --input-type=module - http://web:8080 40 < v2/tests/race-repeat.mjs
const base = process.argv[2]; const rounds = Number(process.argv[3] ?? 40); const N = 10;
const kst = (ms) => new Date(ms + 9 * 3600e3).toISOString().slice(0, 10);
class C { cookie = null;
  async req(method, path, body) {
    const headers = { Accept: 'application/json' }; if (body) headers['Content-Type'] = 'application/json'; if (this.cookie) headers.Cookie = this.cookie;
    const t = Date.now();
    try { const res = await fetch(base + path, { method, headers, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20000) });
      for (const c of res.headers.getSetCookie()) { const m = /^SESSION=([^;]*)/.exec(c); if (m) this.cookie = `SESSION=${m[1]}`; }
      const text = await res.text(); let json = null; try { json = JSON.parse(text); } catch {}
      return { status: res.status, json, ms: Date.now() - t };
    } catch (e) { return { status: 0, err: String(e.cause?.code ?? e.message), ms: Date.now() - t }; } } }
const clients = [];
for (let i = 0; i < N; i++) { const c = new C(); await c.req('POST', '/api/auth/login', { loginId: `owner${221 + i}`, password: 'test-only' }); c.pet = (await c.req('GET', '/api/pets')).json?.[0]?.petId; clients.push(c); }
let day, slots = [];
for (let n = 2; n <= 12 && slots.length < 2; n++) { day = kst(Date.now() + n * 864e5); slots = (await new C().req('GET', `/api/slots?date=${day}&type=GENERAL`)).json ?? []; }
let bad = 0;
for (let r = 1; r <= rounds; r++) {
  const slot = slots[r % slots.length].slotId;
  const res = await Promise.all(clients.map((c) => c.req('POST', '/api/reservations', { petId: c.pet, slotId: slot })));
  const tally = {}; for (const x of res) { const k = x.status === 0 ? `0(${x.err})` : `${x.status}${x.json?.code ? ' ' + x.json.code : ''}`; tally[k] = (tally[k] ?? 0) + 1; }
  const ok = res.filter((x) => x.status === 201).length === 1 && res.filter((x) => x.status === 409).length === N - 1;
  const max = Math.max(...res.map((x) => x.ms));
  if (!ok) { bad++; console.log(`${new Date().toISOString().slice(11, 19)}Z 회차 ${r}: ${JSON.stringify(tally)} 최대 ${max}ms`); }
  for (let i = 0; i < N; i++) if (res[i].status === 201) await clients[i].req('DELETE', `/api/reservations/${res[i].json.reservationId}`);
  if (!ok) break;
}
console.log(`끝: ${rounds}회 중 비정상 ${bad}회`);
