// 브라우저 시연 녹화: EKS 의 ALB 주소로 실제 앱을 조작하며 화면을 그대로 녹화한다.
// 화면 위 자막과 커서 점은 보는 사람을 위한 표시다 (앱의 응답·데이터는 건드리지 않는다).
//   node demo.mjs          → video/ 에 .webm
//   node demo.mjs --dry    → 녹화 없이 단계마다 스크린샷 (step-*.png)
import { chromium } from 'playwright';
import fs from 'fs';
const DRY = process.argv.includes('--dry');
const A1 = fs.readFileSync(new URL('../../_run/alb.env', import.meta.url), 'utf8').match(/A1=(\S+)/)[1];
const B = `http://${A1}`;
const W = 1600, H = 900;
const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: 1, locale: 'ko-KR',
  ...(DRY ? {} : { recordVideo: { dir: 'video', size: { width: W, height: H } } }) });
const p = await ctx.newPage();
let n = 0;
const wait = (ms) => p.waitForTimeout(ms);
const shot = async (name) => { if (DRY) await p.screenshot({ path: `step-${String(++n).padStart(2, '0')}-${name}.png` }); };

// 자막과 커서 점: 페이지가 바뀔 때마다 다시 붙인다
await ctx.addInitScript(() => {
  const add = () => {
    if (document.getElementById('demo-cap')) return;
    const c = document.createElement('div'); c.id = 'demo-cap';
    c.style.cssText = 'position:fixed;left:50%;top:150px;transform:translateX(-50%);z-index:2147483647;background:rgba(15,23,42,.88);color:#fff;font:600 22px/1.4 "Malgun Gothic",sans-serif;padding:12px 26px;border-radius:12px;pointer-events:none;max-width:80%;text-align:center;transition:opacity .3s';
    c.textContent = sessionStorage.getItem('demo-cap') || ''; c.style.opacity = c.textContent ? 1 : 0;
    const d = document.createElement('div'); d.id = 'demo-cur';
    d.style.cssText = 'position:fixed;width:22px;height:22px;margin:-11px 0 0 -11px;border-radius:50%;background:rgba(239,68,68,.55);border:2px solid #b91c1c;z-index:2147483647;pointer-events:none;left:-50px;top:-50px;transition:left .25s,top .25s';
    const xy = sessionStorage.getItem('demo-xy'); if (xy) { const [x, y] = xy.split(','); d.style.left = x + 'px'; d.style.top = y + 'px'; }
    document.documentElement.append(c, d);
    addEventListener('mousemove', (e) => { d.style.left = e.clientX + 'px'; d.style.top = e.clientY + 'px'; sessionStorage.setItem('demo-xy', e.clientX + ',' + e.clientY); }, true);
  };
  if (document.readyState === 'loading') addEventListener('DOMContentLoaded', add); else add();
});
const cap = async (text) => {
  await p.evaluate((t) => { sessionStorage.setItem('demo-cap', t); const c = document.getElementById('demo-cap'); if (c) { c.textContent = t; c.style.opacity = t ? 1 : 0; } }, text).catch(() => {});
};
// 사람이 하듯 요소로 마우스를 옮긴 뒤 누른다
const click = async (loc, pause = 700) => {
  await loc.scrollIntoViewIfNeeded(); const bx = await loc.boundingBox();
  await p.mouse.move(bx.x + bx.width / 2, bx.y + bx.height / 2, { steps: 15 }); await wait(350);
  await loc.click(); await wait(pause);
};
const type = async (loc, text) => { await click(loc, 200); await loc.pressSequentially(text, { delay: 70 }); };
const login = async (id) => {
  await type(p.locator('main input').first(), id);
  await type(p.locator('main input[type=password]'), 'test-only');
  await click(p.locator('main button', { hasText: '로그인' }), 2500);
};

// 1. ALB 로 접속
await p.goto(B + '/'); await cap(`EKS 의 ALB 주소로 접속 — ${A1.split('.')[0]}…elb.amazonaws.com`); await wait(3500); await shot('home');
await p.mouse.wheel(0, 500); await wait(1500); await p.mouse.wheel(0, -500); await wait(800);

// 2. 보호자 로그인
await cap('보호자로 로그인 (시험 계정 owner001)');
await click(p.locator('header a', { hasText: '온라인 예약' }).first(), 1500);
await login('owner001'); await shot('owner-login');

// 3. 예약 등록
await p.goto(B + '/app/reserve'); await wait(1500);
await cap('① 등록 — 반려동물, 진료 항목, 날짜, 시간을 고르고 신청');
await click(p.getByRole('radio', { name: /^콩이/ }));
await click(p.getByRole('radio', { name: /^일반 진료/ }));
const day = p.locator('.date-chip:not(.is-closed)').nth(2);
await click(day, 1500);
const slot = p.locator('.time-grid[role=radiogroup] button:not([disabled])').first();
await slot.waitFor(); await click(slot, 900); await shot('reserve-picked');
await click(p.locator('main button.btn--block', { hasText: '예약 신청' }), 2500); await shot('reserve-done');

// 4. 조회와 수정
await cap('② 조회 — 내 예약에 방금 신청한 예약이 보인다');
await p.goto(B + '/app/reservations'); await wait(2500); await shot('my-list');
await cap('③ 수정 — 예약 시간을 바꾼다');
const myCard = p.locator('main li, main article').filter({ hasText: '콩이' }).filter({ hasText: '승인 대기' }).first();
await click(myCard.locator('button', { hasText: '변경' }), 1500);
const modal = p.locator('dialog[open]');
const slot2 = modal.locator('.time-grid button:not([disabled])').nth(1);
await slot2.waitFor(); await click(slot2, 900); await shot('change-picked');
await click(modal.locator('button.btn--primary'), 2500); await shot('changed');

// 5. 간호사 승인
await cap('간호사로 다시 로그인 → 같은 예약을 승인');
await click(p.locator('header button, header [aria-haspopup]').filter({ hasText: /보호자님|owner|님/ }).first(), 600).catch(() => {});
const out = p.locator('button', { hasText: '로그아웃' }).first();
if (await out.isVisible()) await click(out, 1500); else { await ctx.clearCookies(); }
await p.goto(B + '/app/login'); await wait(1000);
await login('admin1'); await shot('nurse');
await wait(1000);
await click(p.locator('tr', { hasText: /^\s*\d+\/\d+/ }).nth(2), 2000); // 예약한 날 (오늘부터 세 번째 진료일)
await click(p.locator('button', { hasText: /^승인대기/ }), 1500); await shot('nurse-day');
const row = p.locator('tbody tr').filter({ hasText: '콩이' }).filter({ hasText: '승인대기' }).first();
await click(row, 2000);
await click(row.locator('button', { hasText: '승인' }), 2500); await shot('approved');
await cap('승인 완료 — 오른쪽 상세의 "처리 WAS" 가 이 예약을 처리한 Pod 이름');
await wait(3500);

// 6. 여러 Pod 가 응답한다: 화면 맨 아래 줄 (마지막으로 응답한 web Pod · 서비스 Pod)
const foot = p.locator('footer, [class*=footer], [class*=status]').filter({ hasText: 'WEB' }).last();
await foot.evaluate((e) => { e.style.outline = '4px solid #ef4444'; e.style.outlineOffset = '-4px'; }).catch(() => {});
await cap('맨 아래 줄 = 방금 응답한 web Pod 와 서비스 Pod 의 이름');
await click(p.locator('button', { hasText: '새로고침' }), 3500);
await foot.evaluate((e) => { e.style.outline = ''; }).catch(() => {});
const dist = p.locator('section, div').filter({ has: p.getByText('처리 WAS 분포') }).last();
await dist.evaluate((e) => { e.style.outline = '4px solid #ef4444'; }).catch(() => {});
await cap('처리 WAS 분포 — 예약을 처리한 reservation Pod 가 여럿 (복제본 2개가 나눠 처리)');
await wait(4500); await shot('pods');
await dist.evaluate((e) => { e.style.outline = ''; }).catch(() => {});

// 7. 보호자 화면에서 확정 확인
await cap('보호자로 다시 로그인 → 같은 예약이 「예약 확정」');
await click(p.locator('button', { hasText: '로그아웃' }).first(), 1500);
await p.goto(B + '/app/login'); await wait(800);
await login('owner001');
await p.goto(B + '/app/reservations'); await wait(4000); await shot('owner-confirmed');
await cap(''); await wait(1500);
await ctx.close(); await b.close();
if (!DRY) console.log('녹화:', fs.readdirSync('video').map((f) => 'video/' + f).join(', '));
