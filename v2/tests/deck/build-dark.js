// 발표 자료 (다크 테크): v2/docs 의 단계별 문서와 실제 캡처로 만든다. 숫자는 모두 문서·캡처와 같은 값이다.
//   NODE_PATH=node_modules PPTX_SKILL=<pptx 스킬 폴더> node build-dark.js
const pptxgen = require('pptxgenjs');
const fs = require('fs');
const path = require('path');
const { applyTheme } = require(process.env.PPTX_SKILL + '/scripts/apply_theme.js');

const TERM = path.join(__dirname, 'term'); // 제목줄·빈 영역을 자른 실제 터미널 캡처
const DARK = path.join(__dirname, 'dark'); // 어두운 판 구성도
const FIG = path.join(__dirname, 'fig');
const SIZES = JSON.parse(fs.readFileSync(path.join(__dirname, 'sizes.json'), 'utf8'));
const OUT = path.resolve(__dirname, '../../docs/발표-보듬-EKS.pptx');
const VIDEO = path.resolve(__dirname, '../../docs/video/시연-EKS.mp4');

const THEME = {
  name: 'Bodeum Dark',
  headFontFace: 'Malgun Gothic',
  bodyFontFace: 'Malgun Gothic',
  colors: {
    dk1: '0E1412', lt1: 'EEF3F0', dk2: '151C19', lt2: '8A9C94',
    accent1: '3DDC84', accent2: 'FF6B6B', accent3: '26332D', accent4: '5FB3F0', accent5: 'F2C14E', accent6: '1C2622',
    hlink: '3DDC84', folHlink: '8A9C94',
  },
};
const H = THEME.colors;
const MONO = 'Consolas';

const pres = new pptxgen();
pres.layout = 'LAYOUT_WIDE'; // 13.33 x 7.5
pres.title = '보듬 동물병원 예약 시스템 — 컨테이너에서 EKS 까지';
pres.author = 'vet2 캡스톤';
pres.theme = { headFontFace: THEME.headFontFace, bodyFontFace: THEME.bodyFontFace };
const C = pres.SchemeColor;
// C.text1 = 배경색(어두움), C.background1 = 본문 글자(밝음), C.text2 = 판 색, C.background2 = 흐린 글자
const BG = C.text1, FG = C.background1, PANEL = C.text2, MUTED = C.background2, GREEN = C.accent1, RED = C.accent2, LINE = C.accent3, PANEL2 = C.accent6;

pres.defineSlideMaster({
  title: 'COVER',
  background: { color: BG },
  objects: [
    { placeholder: { options: { name: 'title', type: 'title', x: 0.75, y: 2.15, w: 7.2, h: 2.1, fontSize: 50, bold: true, color: FG, valign: 'bottom', align: 'left', margin: 0 }, text: '' } },
  ],
});
pres.defineSlideMaster({
  title: 'CONTENT',
  background: { color: BG },
  objects: [
    { placeholder: { options: { name: 'kicker', type: 'body', x: 0.6, y: 0.35, w: 10, h: 0.3, fontSize: 12, bold: true, color: GREEN, fontFace: MONO, align: 'left', margin: 0 }, text: '' } },
    { placeholder: { options: { name: 'title', type: 'title', x: 0.6, y: 0.68, w: 12.1, h: 0.7, fontSize: 30, bold: true, color: FG, valign: 'top', align: 'left', margin: 0 }, text: '' } },
  ],
  slideNumber: { x: 12.25, y: 7.0, w: 0.5, h: 0.3, fontSize: 10, color: MUTED, fontFace: MONO, align: 'right' },
});

// ── 도우미 ──
const size = (key) => SIZES[key];
const fitBox = (iw, ih, b, top) => {
  const r = Math.min(b.w / iw, b.h / ih), w = iw * r, h = ih * r;
  return { x: b.x + (b.w - w) / 2, y: top ? b.y : b.y + (b.h - h) / 2, w, h };
};
// 터미널 캡처 판: 어두운 판 + 위쪽 이름표(무엇의 캡처인지) + 캡처
const term = (s, name, b, label, opt = {}) => {
  const [iw, ih] = size('t-' + name);
  const pad = 0.12, head = 0.34;
  const f = fitBox(iw, ih, { x: b.x + pad, y: b.y + head, w: b.w - 2 * pad, h: b.h - head - pad }, true);
  const ph = f.h + head + pad;
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: b.x, y: b.y, w: b.w, h: ph, rectRadius: 0.06, fill: { color: '0A0F0D' }, line: { color: opt.edge || LINE, width: 1 }, objectName: '캡처 판 ' + name });
  s.addShape(pres.shapes.OVAL, { x: b.x + 0.16, y: b.y + 0.12, w: 0.11, h: 0.11, fill: { color: opt.dot || MUTED }, line: { type: 'none' }, objectName: '표시 점' });
  s.addText(label, { x: b.x + 0.35, y: b.y + 0.04, w: b.w - 0.5, h: 0.27, fontSize: 11, fontFace: MONO, color: opt.dot || MUTED, valign: 'middle', margin: 0, isTextBox: true });
  s.addImage({ path: path.join(TERM, name), x: f.x, y: f.y, w: f.w, h: f.h, altText: opt.alt || label, objectName: '캡처 ' + name });
  return { bottom: b.y + ph };
};
const diagram = (s, name, b, alt) => {
  const [iw, ih] = size('d-' + name);
  const f = fitBox(iw, ih, b, false);
  s.addImage({ path: path.join(DARK, name), x: f.x, y: f.y, w: f.w, h: f.h, altText: alt, objectName: '구성도 ' + name });
  return f;
};
// 큰 숫자 + 설명 (판 없이 글자만)
const big = (s, x, y, w, num, label, opt = {}) => {
  s.addText(num, { x, y, w, h: opt.h || 0.95, fontSize: opt.size || 54, bold: true, fontFace: MONO, color: opt.color || GREEN, valign: 'bottom', margin: 0, isTextBox: true, fit: 'shrink' });
  s.addText(label, { x, y: y + (opt.h || 0.95) + 0.05, w, h: opt.lh || 0.6, fontSize: opt.lsize || 14, color: MUTED, valign: 'top', margin: 0, isTextBox: true });
};
const text = (s, x, y, w, h, runs, size = 15, opt = {}) => s.addText(runs, { x, y, w, h, fontSize: size, color: FG, valign: opt.valign || 'top', margin: 0, paraSpaceAfter: opt.space ?? 6, isTextBox: true, ...opt.extra });
const line = (s, x, y, w) => s.addShape(pres.shapes.LINE, { x, y, w, h: 0, line: { color: LINE, width: 1 }, objectName: '구분선' });
const vline = (s, x, y, h) => s.addShape(pres.shapes.LINE, { x, y, w: 0, h, line: { color: LINE, width: 1 }, objectName: '세로 구분선' });
const dark = (rows, opts) => rows.map((r, i) => r.map((t, j) => {
  const o = typeof t === 'object' ? t : { text: t };
  return { text: o.text, options: {
    bold: i === 0 || o.bold, fontSize: i === 0 ? 12 : opts.size || 15, fontFace: i === 0 ? MONO : undefined,
    color: i === 0 ? MUTED : (o.color || (opts.green && opts.green.includes(j) ? GREEN : FG)),
    fill: { color: i === 0 ? '0A0F0D' : (i % 2 ? PANEL : BG) }, valign: 'middle',
    border: [{ type: 'none' }, { type: 'none' }, { type: 'solid', color: LINE, pt: 0.75 }, { type: 'none' }],
  } };
}));
const content = (section, kicker, title) => {
  const s = pres.addSlide({ masterName: 'CONTENT', sectionTitle: section });
  s.addText(kicker, { placeholder: 'kicker' });
  s.addText(title, { placeholder: 'title' });
  return s;
};

// ════════ 1. 표지 ════════
pres.addSection({ title: '소개' });
{
  const s = pres.addSlide({ masterName: 'COVER', sectionTitle: '소개' });
  s.addText('CAPSTONE · 2026-11', { x: 0.75, y: 1.6, w: 6, h: 0.35, fontSize: 13, bold: true, fontFace: MONO, color: GREEN, margin: 0, isTextBox: true });
  s.addText('보듬 동물병원\n예약 시스템', { placeholder: 'title' });
  s.addText('같은 앱을 세 번 옮겼다', { x: 0.75, y: 4.45, w: 7, h: 0.5, fontSize: 22, color: FG, margin: 0, isTextBox: true });
  s.addText([
    { text: 'source ', options: { color: MUTED } }, { text: '→ ', options: { color: GREEN } },
    { text: 'docker ', options: { color: MUTED } }, { text: '→ ', options: { color: GREEN } },
    { text: 'kubeadm ', options: { color: MUTED } }, { text: '→ ', options: { color: GREEN } },
    { text: 'EKS', options: { color: FG, bold: true } }, { text: '  (+ RDS)', options: { color: MUTED } },
  ], { x: 0.75, y: 5.1, w: 7.2, h: 0.45, fontSize: 18, fontFace: MONO, margin: 0, isTextBox: true });
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 8.6, y: 0.85, w: 4.1, h: 5.8, rectRadius: 0.1, fill: { color: PANEL }, line: { color: LINE, width: 1 }, objectName: '앱 화면 판' });
  s.addImage({ path: path.join(FIG, 'cover-intro.png'), x: 8.75, y: 1.0, w: 3.8, h: 5.5, sizing: { type: 'cover', w: 3.8, h: 5.5 }, altText: '보듬 동물병원 앱의 소개 페이지 화면', objectName: '앱 화면' });
  s.addNotes('무엇을 세 번 옮겼는지부터. 동물병원 예약 앱을 소스에서 시작해 컨테이너, EC2 의 kubeadm, EKS 로 옮겼고, 선택 과제로 DB 를 RDS 로 옮겼습니다. 모든 단계에서 같은 시나리오 테스트로 확인했고, 화면에 나오는 명령 결과는 모두 실제 터미널 캡처입니다.');
}

// ════════ 2. 워크로드 ════════
{
  const s = content('소개', '00 · WORKLOAD', '서비스 3개, 상태를 가진 것은 둘');
  diagram(s, 'arch-components.png', { x: 0.45, y: 1.55, w: 8.7, h: 4.6 }, '구성 요소 그림: web, auth, clinic, reservation, MySQL, Redis');
  big(s, 9.6, 1.7, 3.2, '6', '구성 요소\nweb · 서비스 3 · MySQL · Redis', { size: 64, h: 1.1, lh: 0.75 });
  line(s, 9.6, 3.75, 3.1);
  big(s, 9.6, 3.95, 3.2, '2', '상태를 가진 것\n끝까지 한계로 남았다', { size: 64, h: 1.1, lh: 0.75, color: RED });
  text(s, 0.6, 6.45, 12, 0.4, [{ text: 'Java 21 · Spring Boot · :8080 · /health — 설정은 모두 환경 변수, 서비스끼리는 부르지 않는다', options: { color: MUTED } }], 14);
  s.addNotes('구성 요소는 6개입니다. web 은 Apache 로 화면과 API 경로를 나누고, 서비스 3개는 로그인, 반려동물과 공지, 예약을 맡습니다. 데이터는 MySQL 에, 로그인 세션은 Redis 에 있습니다. 이 두 개가 상태를 가진 부품이고, 발표 끝까지 이 둘이 계속 문제의 중심이 됩니다.');
}

// ════════ 3. 단계별 변화 ════════
{
  const s = content('소개', '00 · OVERVIEW', '같은 시나리오로 네 단계를 확인했다');
  diagram(s, 'arch-flow.png', { x: 0.45, y: 1.5, w: 12.4, h: 3.75 }, '네 단계 흐름: 워크로드, 컨테이너, kubeadm, EKS');
  const st = [['① jar', '60 / 60'], ['② compose', '65 / 65'], ['③ kubeadm', '65 / 65'], ['④ EKS', '65 / 65']];
  line(s, 0.6, 5.5, 12.1);
  st.forEach(([k, v], i) => {
    const x = 0.6 + i * 3.05;
    if (i) vline(s, x - 0.2, 5.75, 1.15);
    big(s, x, 5.6, 2.8, v, '시나리오 · ' + k, { size: 34, h: 0.75, lh: 0.4 });
  });
  s.addNotes('①에서 jar 를 직접 띄우고, ②에서 컨테이너로, ③에서 EC2 3대에 직접 만든 쿠버네티스로, ④에서 EKS 로 옮겼습니다. 화면이 쓰는 API 를 묶은 시나리오 테스트 하나를 모든 단계에서 그대로 돌렸고, ②부터는 화면 항목이 더해져 65개입니다. 소스는 고치지 않았습니다.');
}

// ════════ 4. ① 테스트 환경 ════════
pres.addSection({ title: '① 워크로드 테스트' });
{
  const s = content('① 워크로드 테스트', '01 · WORKLOAD TEST · WSL 2', '모든 단계가 쓰는 시나리오를 먼저 만들었다');
  big(s, 0.6, 1.65, 4.2, '60/60', '시나리오 테스트 통과 · 11묶음', { size: 60, h: 1.15 });
  const items = ['WSL 2 Ubuntu · JDK 21 · Docker', '등록 → 조회 → 수정', '직원 화면 · 동시 신청 · 로그인 제한', 'DB 계정 경계 9개', '②③④ 에서 주소만 바꿔 같은 파일로'];
  text(s, 0.6, 3.6, 4.2, 3, items.map((t, i) => ({ text: t, options: { bullet: { characterCode: '25B8' }, breakLine: i < items.length - 1 } })), 16, { space: 10 });
  term(s, '1-07-scenario.png', { x: 5.15, y: 1.6, w: 7.6, h: 5.3 }, 'scenario.mjs · WSL 2 · 2026-11-24', { alt: '시나리오 테스트 결과 통과 60, 실패 0 터미널 캡처' });
  s.addNotes('테스트 환경은 WSL 2 Ubuntu 입니다. 문서만 보고 같은 환경을 만들 수 있게 버전과 명령을 남겼습니다. 시나리오는 예약 등록, 조회, 수정과 직원 화면, 동시 신청, DB 계정 경계까지 60항목이고, 이후 모든 단계에서 같은 파일을 씁니다.');
}

// ════════ 5. ② 빌드 최적화 ════════
pres.addSection({ title: '② 이미지·컨테이너' });
{
  const s = content('② 이미지·컨테이너', '02 · IMAGE BUILD', '방법을 하나씩 더하며 쟀다');
  const labels = ['A 처음', 'B ignore', 'C 두 단계', 'D alpine', 'E 캐시'];
  const common = {
    y: 1.55, w: 6.0, h: 3.75, barDir: 'col', showTitle: true, titleFontSize: 14, titleColor: H.lt2, titleFontFace: '+mn-lt',
    showValue: true, dataLabelPosition: 'outEnd', dataLabelFontSize: 13, dataLabelColor: H.lt1, dataLabelFontFace: MONO,
    catAxisLabelColor: H.lt2, catAxisLabelFontSize: 12, catAxisLabelFontFace: '+mn-lt', catAxisLineShow: true, catAxisLineColor: H.accent3,
    valAxisHidden: true, valGridLine: { style: 'none' }, catGridLine: { style: 'none' }, showLegend: false, barGapWidthPct: 55,
  };
  s.addChart(pres.charts.BAR, [{ name: '이미지 크기 (MB)', labels, values: [1520, 1310, 550, 366, 366] }],
    { ...common, x: 0.45, title: '이미지 크기 (MB)', dataLabelFormatCode: '#,##0', chartColors: ['3A4A43', '3A4A43', '3A4A43', '3DDC84', '3DDC84'], objectName: '이미지 크기 차트' });
  s.addChart(pres.charts.BAR, [{ name: '재빌드 (초)', labels, values: [54.8, 46.7, 33.5, 31.4, 12.1] }],
    { ...common, x: 6.85, title: '소스 한 줄 고친 뒤 재빌드 (초)', dataLabelFormatCode: '0.0', chartColors: ['3A4A43', '3A4A43', '3A4A43', '3A4A43', '3DDC84'], objectName: '재빌드 시간 차트' });
  line(s, 0.6, 5.55, 12.1);
  big(s, 0.6, 5.65, 3.6, '366MB', '1.52GB 에서 −76%', { size: 40, h: 0.8, lh: 0.4 });
  big(s, 4.4, 5.65, 3.6, '12.1s', '54.8초에서 −78%', { size: 40, h: 0.8, lh: 0.4 });
  text(s, 8.3, 5.8, 4.4, 1.2, [
    { text: '두 단계 빌드 → 실행 이미지에 JRE 만', options: { breakLine: true } },
    { text: 'Gradle 캐시 → 의존성 층을 다시 받지 않음' },
  ], 14, { space: 8 });
  s.addNotes('이미지 빌드는 방법을 하나씩 더하며 같은 조건으로 쟀습니다. .dockerignore 로 빌드 맥락이 112MB 에서 7kB 로, 두 단계 빌드로 실행 이미지에 JRE 만 남겨 550MB, alpine 으로 366MB. 마지막에 Gradle 캐시를 남기자 소스 한 줄 고친 뒤 재빌드가 54.8초에서 12.1초가 됐습니다.');
}

// ════════ 6. ② 실행·배포 ════════
{
  const s = content('② 이미지·컨테이너', '02 · CONTAINERS', '6개 모두 healthy, root 가 아니고, ECR 에 올라갔다');
  const a = term(s, '2-06-ps.png', { x: 0.6, y: 1.55, w: 8.3, h: 2.0 }, 'docker compose ps · 6개 healthy', { alt: 'compose ps 6개 컨테이너 healthy' });
  const b2 = term(s, '2-07-user.png', { x: 0.6, y: a.bottom + 0.15, w: 8.3, h: 2.0 }, '실행 사용자 · root 없음', { alt: '컨테이너 6개 실행 사용자 uid, root 아님' });
  term(s, '2-13-push.png', { x: 0.6, y: b2.bottom + 0.15, w: 8.3, h: 2.0 }, 'ECR push · 계정 번호 가림', { alt: 'ECR push 결과' });
  big(s, 9.3, 1.75, 3.45, '20→1~2', '종료 때 끊긴 요청\n(강제 종료 → 종료 신호)', { size: 40, h: 0.85, lh: 0.75 });
  line(s, 9.3, 3.65, 3.45);
  big(s, 9.3, 3.85, 3.45, '≠ 0', '종료 신호를 받게 했지만 남았다\n기준을 다 채우지 못함', { size: 40, h: 0.85, lh: 0.75, color: RED });
  line(s, 9.3, 5.75, 3.45);
  text(s, 9.3, 5.9, 3.45, 0.8, [{ text: 'web 82 · 서비스 10001\nMySQL·Redis 999', options: { color: MUTED, fontFace: MONO } }], 13);
  s.addNotes('compose 로 6개를 띄우면 healthcheck 가 모두 통과합니다. 실행 사용자는 모두 root 가 아니고, ECR 에 push 했습니다. 다 채우지 못한 기준도 있습니다. 종료 신호를 자바가 받게 고쳐서 끊기는 요청이 20건에서 1~2건으로 줄었지만 0 은 아닙니다.');
}

// ════════ 7. ③ 클러스터 구축 ════════
pres.addSection({ title: '③ 쿠버네티스' });
{
  const s = content('③ 쿠버네티스', '03 · KUBEADM', 'EC2 3대, 필요한 포트만 열었다');
  diagram(s, 'arch-kubeadm.png', { x: 0.45, y: 1.55, w: 6.0, h: 3.9 }, 'kubeadm 클러스터 구성도');
  const a = term(s, '3-01-nodes.png', { x: 6.65, y: 1.55, w: 6.1, h: 1.3 }, 'kubectl get nodes · 3대 Ready', { alt: '노드 3대 Ready' });
  term(s, '3-02-sg.png', { x: 6.65, y: a.bottom + 0.15, w: 6.1, h: 2.4 }, '보안 그룹 vet2-nodes · IP 가림', { alt: '보안 그룹 규칙 5줄' });
  line(s, 0.6, 5.7, 12.1);
  const rows = [['MetalLB (L2)', 'NodePort', 'VPC 에서는 L2 광고가 동작하지 않는다'], ['Calico', 'Flannel', 'Pod 끼리 통신만 필요, 부품이 적다']];
  text(s, 0.6, 5.85, 2.2, 0.3, [{ text: '수업과 다르게', options: { color: MUTED, fontFace: MONO, bold: true } }], 12);
  rows.forEach((r, i) => {
    const y = 6.2 + i * 0.42;
    text(s, 0.6, y, 12, 0.38, [
      { text: r[0], options: { color: MUTED } }, { text: '  →  ', options: { color: GREEN } },
      { text: r[1], options: { bold: true } }, { text: '   ' + r[2], options: { color: MUTED } },
    ], 15, { valign: 'middle' });
  });
  s.addNotes('EC2 3대에 kubeadm 으로 컨트롤 플레인 1대, 워커 2대를 만들었습니다. 밖에서는 웹과 kubectl 포트만 이 PC 의 IP 에 열고, 노드끼리는 Flannel, API 서버, kubelet 포트만 엽니다. 수업과 다르게 한 것이 둘인데, EC2 에서는 MetalLB L2 가 동작하지 않아 NodePort 를, 네트워크 플러그인은 Flannel 을 골랐습니다.');
}

// ════════ 8. ③ 무중단 배포 ════════
{
  const s = content('③ 쿠버네티스', '03 · ROLLOUT · 같은 클러스터에서 v0 와 비교', '다시 배포 중 실패');
  s.addText([{ text: '240', options: { color: RED } }, { text: ' → ', options: { color: MUTED } }, { text: '0', options: { color: GREEN } }],
    { x: 6.2, y: 0.45, w: 6.55, h: 1.05, fontSize: 60, bold: true, fontFace: MONO, align: 'right', valign: 'middle', margin: 0, isTextBox: true });
  term(s, 'prob-3-k1-rollout.png', { x: 0.6, y: 1.65, w: 6.0, h: 3.6 }, 'v0 · 305건 중 240건 503', { dot: RED, edge: '5A2A2A', alt: 'v0 다시 배포 중 실패 240건' });
  term(s, '3-06-ops.png', { x: 6.75, y: 1.65, w: 6.0, h: 3.6 }, '최종 · 7,188건 중 0건', { dot: GREEN, edge: '1F5A3A', alt: '최종 다시 배포 실패 0건' });
  const fx = [['준비 전에 요청을 받음', 'startup · readiness probe'], ['복제본이 하나', '복제본 2 · maxUnavailable 0'], ['내려가는 Pod 가 요청을 끊음', 'preStop 으로 잠깐 기다림']];
  text(s, 0.6, 4.75, 2.5, 0.3, [{ text: '원인 셋 → 고친 것 셋', options: { color: MUTED, fontFace: MONO, bold: true } }], 12);
  line(s, 0.6, 5.1, 12.1);
  fx.forEach(([a, b], i) => {
    const x = 0.6 + i * 4.1;
    if (i) vline(s, x - 0.2, 5.3, 1.0);
    text(s, x, 5.25, 3.85, 1.1, [{ text: a, options: { color: MUTED, breakLine: true } }, { text: b, options: { bold: true, color: GREEN } }], 17, { space: 6 });
  });
  line(s, 0.6, 6.45, 12.1);
  text(s, 0.6, 6.6, 12.1, 0.35, [{ text: '업데이트·롤백 125 → 2건 · 남은 2건은 연결 끊김, 원인 미확인 (같은 파일로 EKS 는 0건)', options: { color: MUTED } }], 13);
  s.addNotes('가장 단순한 배포 v0 를 같은 클러스터에 띄우고 요청을 계속 보내며 다시 배포했더니 305건 중 240건이 503 이었습니다. 원인은 셋이 겹쳐 있었습니다. probe, 복제본 2개와 maxUnavailable 0, preStop 을 모두 넣자 7천여 건 중 0건. 업데이트·롤백은 125건에서 2건까지 줄었는데, 남은 2건은 연결 끊김이고 원인을 찾지 못했다고 문서에 밝혔습니다.');
}

// ════════ 9. ③ 데이터·설정 ════════
{
  const s = content('③ 쿠버네티스', '03 · DATA & CONFIG', 'MySQL Pod 를 지워도 예약이 남는다');
  const a = term(s, 'prob-3-k2-data-lost.png', { x: 0.6, y: 1.55, w: 12.1, h: 2.0 }, 'v0 · 볼륨 없는 Deployment', { dot: RED, edge: '5A2A2A', alt: 'v0 MySQL Pod 삭제 뒤 예약 176 없음' });
  const b2 = term(s, '3-10-db-replace.png', { x: 0.6, y: a.bottom + 0.15, w: 12.1, h: 2.0 }, '최종 · StatefulSet + 볼륨', { dot: GREEN, edge: '1F5A3A', alt: 'MySQL Pod 삭제 뒤 예약 217 남음' });
  const y0 = b2.bottom + 0.25;
  big(s, 0.6, y0, 3.8, '#176 ✕', 'v0: 예약이 사라졌다', { size: 40, h: 0.8, lh: 0.4, color: RED });
  vline(s, 4.4, y0 + 0.15, 1.1);
  big(s, 4.65, y0, 3.8, '#217 ✓', '최종: 그대로 남았다', { size: 40, h: 0.8, lh: 0.4 });
  vline(s, 8.45, y0 + 0.15, 1.1);
  big(s, 8.7, y0, 4.0, '16 → 0', '배포 정보에 보이던 비밀번호 줄', { size: 40, h: 0.8, lh: 0.4 });
  s.addNotes('v0 는 MySQL 을 볼륨 없이 띄워서 Pod 를 지우자 예약 176번이 사라졌습니다. StatefulSet 과 볼륨으로 바꾼 뒤에는 217번이 남았습니다. 비밀번호는 v0 에서 배포 정보에 16줄 그대로 보였고, Secret 으로 옮겨 0줄이 됐습니다. 다만 교체하는 11초 동안은 DB 요청이 실패합니다.');
}

// ════════ 10. ③ 노드 장애 ════════
{
  const s = content('③ 쿠버네티스', '03 · NODE FAILURE', '기본값은 "오래 기다리기"였다');
  diagram(s, 'node-failure-timeline.png', { x: 0.45, y: 1.5, w: 8.6, h: 2.75 }, '노드 장애 타임라인: 고치기 전 393초, 고친 뒤 115초');
  big(s, 9.4, 1.55, 3.4, '393→115s', '앱만 있는 워커가 죽은 뒤 전부 복구', { size: 36, h: 0.75, lh: 0.45 });
  big(s, 9.4, 2.9, 3.4, '675→110', '그동안 실패한 요청', { size: 36, h: 0.75, lh: 0.45 });
  const items = [
    ['K-9', '노드가 죽어도 300초 동안 Pod 를 옮기지 않음', 'tolerationSeconds 30', GREEN],
    ['K-10', '클러스터 DNS 둘이 한 노드에 → 그 노드와 함께 모든 요청 실패', 'CoreDNS 를 두 노드에', GREEN],
    ['K-11', 'DB 가 있는 노드가 죽으면 DB 가 옮겨 가지 못함', '한계 → 선택 과제 RDS', RED],
  ];
  line(s, 0.6, 4.45, 12.1);
  items.forEach(([k, a, b, col], i) => {
    const y = 4.6 + i * 0.68;
    text(s, 0.6, y, 0.9, 0.55, [{ text: k, options: { bold: true, color: col, fontFace: MONO } }], 15, { valign: 'middle' });
    text(s, 1.55, y, 7.2, 0.55, [{ text: a }], 15, { valign: 'middle' });
    text(s, 8.9, y, 3.85, 0.55, [{ text: b, options: { bold: true, color: col } }], 15, { valign: 'middle' });
    line(s, 0.6, y + 0.62, 12.1);
  });
  text(s, 0.6, 6.75, 9, 0.3, [{ text: '타임라인은 2026-11-23 측정 기록으로 그린 것 (③ 6.4)', options: { color: MUTED } }], 12);
  s.addNotes('워커를 강제로 멈추자 쿠버네티스는 기본값대로 300초를 기다린 뒤에야 Pod 를 옮겨서, 393초 동안 로그인이 안 됐습니다. 대기 시간을 30초로 줄여 115초에 전부 복구됐습니다. 클러스터 DNS 가 한 노드에 몰려 있던 문제도 이 실험에서 찾았습니다. DB 가 있는 노드가 죽으면 DB 가 옮겨 가지 못하는 것은 한계로 남겼고, 선택 과제의 RDS 가 이것을 풉니다.');
}

// ════════ 11. ④ EKS 전환 ════════
pres.addSection({ title: '④ EKS' });
{
  const s = content('④ EKS', '04 · EKS AUTO MODE', 'EKS 가 대신한 일, 내가 정해야 했던 일');
  const rows = [
    ['', 'KUBEADM ③', 'EKS AUTO MODE ④'],
    [{ text: '컨트롤 플레인·노드', bold: true }, '직접 init · join, 2대 고정', 'EKS 가 운영, 노드도 자동'],
    [{ text: '이미지 받기', bold: true }, 'ECR 로그인 Secret, 12시간', '노드 IAM 역할 — 할 일 없음'],
    [{ text: '밖으로', bold: true }, 'NodePort 30080', 'Ingress → ALB'],
    [{ text: 'MySQL 볼륨', bold: true }, '워커1 디스크를 PV 로 등록', 'EBS gp3'],
    [{ text: '노드 분산', bold: true }, 'maxSkew 1', '+ minDomains 2, 영역 분산'],
  ];
  s.addTable(dark(rows, { green: [2] }), { x: 0.6, y: 1.6, w: 8.3, colW: [2.2, 2.9, 3.2], rowH: 0.58, margin: [0, 0.12, 0, 0.12], objectName: 'kubeadm 과 EKS 비교' });
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 9.25, y: 1.6, w: 3.5, h: 2.75, rectRadius: 0.08, fill: { color: PANEL }, line: { color: LINE, width: 1 }, objectName: '직접 정한 것 판' });
  const own = ['StorageClass', 'IngressClass', '노드·영역 분산', '정리에서 뺄 Pod'];
  text(s, 9.5, 1.8, 3.1, 3.2, [
    { text: '그래도 직접 정한 것', options: { bold: true, color: GREEN, fontFace: MONO, fontSize: 13, breakLine: true } },
    ...own.map((t, i) => ({ text: `E-${[2, 1, 3, 4][i]}  ${t}`, options: { breakLine: i < own.length - 1 } })),
  ], 16, { space: 10 });
  line(s, 0.6, 5.35, 12.1);
  text(s, 0.6, 5.5, 12.1, 1.3, [
    { text: 'E-3  ', options: { bold: true, color: GREEN, fontFace: MONO } }, { text: 'Auto Mode 가 노드를 줄이며 Pod 를 한 노드에 몰았다 → minDomains 2', options: { breakLine: true } },
    { text: 'E-4  ', options: { bold: true, color: RED, fontFace: MONO } }, { text: 'MySQL·Redis 를 지키는 표시 때문에 노드가 24시간 안 지워진다 → 맞바꿈, 사람이 옮긴다' },
  ], 15, { space: 10 });
  s.addNotes('EKS 는 컨트롤 플레인과 노드, 이미지 로그인, 로드밸런서와 볼륨 드라이버를 대신해 줍니다. 그래도 StorageClass, IngressClass, 분산 규칙, 정리 예외는 제가 정해야 했고, 그중 둘은 Auto Mode 의 노드 정리 동작 때문에 새로 생긴 문제였습니다.');
}

// ════════ 12. ④ 노출·데이터 ════════
{
  const s = content('④ EKS', '04 · INGRESS & STORAGE', 'ALB 로 열고, StorageClass 는 직접 만들었다');
  diagram(s, 'arch-eks.png', { x: 0.45, y: 1.5, w: 6.4, h: 3.55 }, 'EKS 구성도');
  const a = term(s, 'prob-4-e2-gp2.png', { x: 7.0, y: 1.55, w: 5.75, h: 2.6 }, '문제 · 기본 gp2 → Pending', { dot: RED, edge: '5A2A2A', alt: '기본 gp2 PVC 가 Pending' });
  term(s, '4-03-storage.png', { x: 7.0, y: a.bottom + 0.15, w: 5.75, h: 1.9 }, '고친 뒤 · vet2-ebs → Bound', { dot: GREEN, edge: '1F5A3A', alt: 'vet2-ebs StorageClass, PVC Bound' });
  line(s, 0.6, 5.3, 6.1);
  big(s, 0.6, 5.4, 2.9, '65/65', 'ALB 를 거친 시나리오', { size: 40, h: 0.8, lh: 0.4 });
  big(s, 3.6, 5.4, 3.2, '0/9,700', '다시 배포 중 실패', { size: 40, h: 0.8, lh: 0.4 });
  text(s, 7.0, 6.45, 5.75, 0.6, [{ text: 'gp2 는 ebs.csi.aws.com 을 기다리는데 Auto Mode 의 드라이버는 ebs.csi.eks.amazonaws.com', options: { color: MUTED } }], 12);
  s.addNotes('밖으로는 Ingress 하나로 ALB 를 만들고, Pod IP 로 바로 보내며 이 PC 의 IP 에서만 받게 했습니다. 볼륨은 클러스터에 처음부터 있는 gp2 로는 영영 만들어지지 않았습니다. 기다리는 드라이버 이름과 Auto Mode 의 드라이버 이름이 달라서입니다. gp3 StorageClass 를 직접 만들어 해결했고, MySQL Pod 를 지워도 예약이 남았습니다. 다시 배포, 업데이트·롤백 모두 실패 0건이었습니다.');
}

// ════════ 13. 선택 과제 RDS ════════
pres.addSection({ title: '선택 과제·회고' });
{
  const s = content('선택 과제·회고', 'OPTIONAL · RDS', 'DB 를 클러스터 밖으로');
  s.addText([{ text: '372', options: { color: RED } }, { text: ' → ', options: { color: MUTED } }, { text: '39', options: { color: GREEN } }],
    { x: 6.2, y: 0.45, w: 6.55, h: 1.05, fontSize: 60, bold: true, fontFace: MONO, align: 'right', valign: 'middle', margin: 0, isTextBox: true });
  diagram(s, 'arch-rds.png', { x: 0.45, y: 1.6, w: 5.9, h: 2.95 }, 'RDS 구성도');
  term(s, '6-12-node-w1.png', { x: 6.5, y: 1.65, w: 6.25, h: 4.0 }, 'node-down.sh · DB 가 있는 워커를 강제 정지', { alt: '필수 구성 372건, RDS 구성 39건 실패' });
  line(s, 0.6, 4.8, 5.65);
  text(s, 0.6, 4.95, 5.65, 1.3, [
    { text: '372', options: { bold: true, color: RED, fontFace: MONO } }, { text: '  클러스터 안 MySQL · 약 1,000건 중', options: { color: MUTED, breakLine: true } },
    { text: '39 ', options: { bold: true, color: GREEN, fontFace: MONO } }, { text: '  RDS 구성 · 약 13,800건 중', options: { color: MUTED } },
  ], 17, { space: 10 });
  line(s, 0.6, 6.15, 5.65);
  text(s, 0.6, 6.3, 12.1, 0.7, [{ text: '사설 서브넷 · 두 노드 보안 그룹에서만 3306 · 연결 한도 60 → 서비스당 연결 3개 · 재시작 뒤 예약 유지', options: { color: MUTED } }], 13);
  s.addNotes('선택 과제로 같은 클러스터에 RDS 를 쓰는 구성을 하나 더 띄웠습니다. 사설 서브넷에 두고 두 클러스터의 노드 보안 그룹에서만 3306 을 받습니다. DB 가 있는 워커를 강제로 멈추고 두 구성에 같은 시간에 요청을 보냈더니, 클러스터 안 MySQL 구성은 372건이 실패하며 끝까지 회복하지 못했고, RDS 구성은 39건이었습니다. 연결 한도 60 을 넘는 문제는 서비스당 연결 수를 3으로 줄여 풀었습니다.');
}

// ════════ 14. 선택 과제 + 회고 ════════
{
  const s = content('선택 과제·회고', 'OPTIONAL · RETROSPECTIVE', '선택 과제와 회고');
  const rows = [
    ['선택 과제', '결과'],
    [{ text: '빌드 최적화', bold: true }, '1.52GB → 366MB · 54.8s → 12.1s'],
    [{ text: '무중단 롤링 업데이트', bold: true }, '③ 240 → 0 · ④ 0 / 9,700'],
    [{ text: 'Kustomize', bold: true }, 'base + overlay 5 + component 1'],
    [{ text: '요청·분산·PDB', bold: true }, 'PDB 가 마지막 복제본을 지킴'],
    [{ text: '가용 영역 분산', bold: true }, '노드 2a · 2c'],
    [{ text: 'RDS', bold: true }, '사설 서브넷 · 두 클러스터 65 / 65'],
    [{ text: 'Secrets Manager', bold: true }, { text: '일부 — RDS 관리자 비밀번호만', color: H.lt2 }],
  ];
  s.addTable(dark(rows, { size: 14 }), { x: 0.6, y: 1.6, w: 6.6, colW: [2.4, 4.2], rowH: 0.52, margin: [0, 0.12, 0, 0.12], objectName: '선택 과제 표' });
  text(s, 0.6, 6.0, 6.6, 0.35, [{ text: '하지 않은 것: Helm · Gateway API · HTTPS · HPA', options: { color: MUTED } }], 13);
  s.addText('관리형은 설치를 없애 주지만,\n동작을 정하는 일은 남긴다', { x: 7.6, y: 1.6, w: 5.15, h: 1.6, fontSize: 24, bold: true, color: FG, valign: 'top', margin: 0, isTextBox: true });
  const cmp = [['kubeadm', '모든 부품이 보이고 고칠 수 있었다. 장애 실험과 대기 시간 조정이 됐다. 볼륨·노출·로그인은 손으로.'],
    ['EKS', '설치와 연결이 사라졌다. 대신 노드 정리가 새 문제 둘을 만들었고, 노드를 멈출 수 없었다.']];
  cmp.forEach(([k, t], i) => {
    const y = 3.45 + i * 1.45;
    line(s, 7.6, y, 5.15);
    text(s, 7.6, y + 0.15, 5.15, 1.2, [{ text: k, options: { bold: true, color: GREEN, fontFace: MONO, breakLine: true } }, { text: t, options: { color: MUTED } }], 15, { space: 4 });
  });
  s.addNotes('선택 과제는 표와 같습니다. Secrets Manager 는 RDS 관리자 비밀번호에만 썼습니다. 회고로, 직접 만든 kubeadm 은 손이 많이 가지만 무엇이 일어나는지 다 보였고, EKS 는 설치와 연결을 없애 주지만 동작을 정하는 일은 남겼습니다. 오히려 관리형이 대신 해 주는 노드 정리 때문에 새 문제가 둘 생겼습니다.');
}

// ════════ 15. 시연 + 비용·정리 ════════
pres.addSection({ title: '시연·정리' });
{
  const s = content('시연·정리', 'DEMO · ALB 주소로 등록 → 조회 → 수정 → 승인', '시연과 비용·정리');
  const cover = 'image/png;base64,' + fs.readFileSync(path.join(FIG, 'video-cover.png')).toString('base64');
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 0.6, y: 1.6, w: 7.6, h: 4.5, rectRadius: 0.06, fill: { color: '0A0F0D' }, line: { color: LINE, width: 1 }, objectName: '영상 판' });
  s.addMedia({ type: 'video', path: VIDEO, cover, x: 0.72, y: 1.72, w: 7.36, h: 4.14, objectName: '시연 영상' });
  text(s, 0.6, 6.25, 7.6, 0.35, [{ text: '실제 녹화 1분 54초 — 시연이 안 될 때 이 영상을 튼다', options: { color: MUTED } }], 13);
  const rows = [['자원', '시간당'], ['EC2 t3.medium × 3', '$0.16'], ['EKS 컨트롤 플레인 + 노드 2', '$0.27+'], ['ALB × 2', '$0.06'], ['RDS db.t4g.micro', '$0.025'], [{ text: '합계', bold: true }, { text: '≈ $0.55', bold: true, color: H.accent1 }]];
  s.addTable(dark(rows, { size: 14 }), { x: 8.55, y: 1.6, w: 4.2, colW: [2.9, 1.3], rowH: 0.45, margin: [0, 0.1, 0, 0.1], objectName: '비용 표' });
  text(s, 8.55, 4.65, 4.2, 1.8, [
    { text: '지우기', options: { bold: true, color: GREEN, fontFace: MONO, fontSize: 13, breakLine: true } },
    { text: '$ stacks.sh down all', options: { fontFace: MONO, bold: true, breakLine: true } },
    { text: 'RDS → Ingress·PVC → EKS\n→ kubeadm → ECR → 네트워크', options: { color: MUTED } },
  ], 14, { space: 6 });
  s.addNotes('ALB 주소로 보호자 로그인, 예약 등록, 조회, 시간 변경을 하고, 간호사로 승인하면 화면 아래에 응답한 Pod 이름이 보입니다. 다시 보호자로 들어가면 예약 확정으로 바뀝니다. 비용은 모두 켜 두면 시간당 약 0.55달러이고, 발표가 끝나면 스택 스크립트 하나로 의존 순서대로 지웁니다. 스택 밖에 생긴 ALB 와 EBS 를 먼저 지우는 것까지 스크립트가 합니다.');
}

// ════════ 16. 예비: 완성 기준 점검표 ════════
pres.addSection({ title: '예비' });
{
  const s = content('예비', 'BACKUP · 질의응답용', '완성 기준 점검표');
  const no = (t) => ({ text: t, color: H.accent2 });
  const rows = [
    ['단계', '기준', '결과'],
    ['①', 'WSL 2 빌드·실행, 시나리오', '빌드 성공 · /health 200 · 60 / 60'],
    ['②', '이미지·compose, root 아님', '6개 healthy · 65 / 65 · 모두 root 아님'],
    ['②', '종료 신호에 요청을 마침', no('1~2건 남음 — 0 은 못 채움')],
    ['③', 'kubeadm 3대, 필요한 포트만', '3대 Ready · 보안 그룹 5줄'],
    ['③', '롤링 업데이트·롤백', no('다시 배포 0건 · 업데이트·롤백 2건 — 0 은 못 채움')],
    ['③', 'DB Pod 교체 뒤 데이터, Secret', '예약 217 유지 · 비밀번호 0줄'],
    ['④', 'ALB, StorageClass, 시나리오', 'ALB · vet2-ebs · 65 / 65'],
    ['④', '무중단·자동 복구·데이터', '모두 실패 0건 · 예약 204·207 유지'],
  ];
  s.addTable(dark(rows, { size: 14 }), { x: 0.6, y: 1.6, w: 12.1, colW: [0.9, 4.4, 6.8], rowH: 0.52, margin: [0, 0.12, 0, 0.12], objectName: '완성 기준 점검표' });
  text(s, 0.6, 6.5, 12.1, 0.3, [{ text: '근거: v2/docs/5-최종문서.md 0.3 — 기준마다 단계별 문서의 절과 캡처', options: { color: MUTED } }], 12);
  s.addNotes('질문이 나오면 쓰는 슬라이드입니다. 다 채우지 못한 기준은 두 개이고, 문서에 그렇게 적었습니다.');
}

(async () => {
  await pres.writeFile({ fileName: OUT });
  await applyTheme(OUT, THEME);
  console.log('저장:', OUT);
})();
