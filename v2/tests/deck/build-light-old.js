// 발표 자료: v2/docs 의 단계별 문서와 실제 캡처로 만든다. 숫자는 모두 문서·캡처와 같은 값이다.
const pptxgen = require('pptxgenjs');
const fs = require('fs');
const path = require('path');
const { applyTheme } = require(process.env.PPTX_SKILL + '/scripts/apply_theme.js');

const SHOT = path.resolve(__dirname, '../../docs/img/shot');
const IMG = path.resolve(__dirname, '../../docs/img');
const FIG = path.resolve(__dirname, 'fig');
const SIZES = JSON.parse(fs.readFileSync(path.join(__dirname, 'sizes.json'), 'utf8'));
const OUT = path.resolve(__dirname, '../../docs/발표-보듬-EKS.pptx');

const THEME = {
  name: 'Bodeum Clinic',
  headFontFace: 'Malgun Gothic',
  bodyFontFace: 'Malgun Gothic',
  colors: {
    dk1: '1B2A24', lt1: 'FFFFFF', dk2: '1F4D3D', lt2: 'EEF4F0',
    accent1: '2E7D5B', accent2: 'F2C14E', accent3: 'C8483F', accent4: '3F6E9A', accent5: '7D8C85', accent6: 'F4B8C5',
    hlink: '2E7D5B', folHlink: '1F4D3D',
  },
};
const HEX = THEME.colors;

const pres = new pptxgen();
pres.layout = 'LAYOUT_WIDE'; // 13.33 x 7.5
pres.title = '보듬 동물병원 예약 시스템 — 컨테이너에서 EKS 까지';
pres.author = 'vet2 캡스톤';
pres.theme = { headFontFace: THEME.headFontFace, bodyFontFace: THEME.bodyFontFace };
const C = pres.SchemeColor;

// ── 레이아웃 ──
pres.defineSlideMaster({
  title: 'TITLE_DARK',
  background: { color: C.text2 },
  objects: [
    { placeholder: { options: { name: 'title', type: 'title', x: 0.7, y: 2.0, w: 7.2, h: 1.9, fontSize: 40, bold: true, color: C.background1, valign: 'bottom', align: 'left', margin: 0 }, text: '' } },
    { placeholder: { options: { name: 'body', type: 'body', x: 0.7, y: 4.1, w: 7.2, h: 1.6, fontSize: 18, color: C.background2, valign: 'top', align: 'left', margin: 0 }, text: '' } },
  ],
});
pres.defineSlideMaster({
  title: 'CONTENT',
  background: { color: C.background1 },
  margin: [0.5, 0.5, 0.6, 0.5],
  objects: [
    { placeholder: { options: { name: 'kicker', type: 'body', x: 0.55, y: 0.28, w: 9, h: 0.32, fontSize: 13, bold: true, color: C.accent1, align: 'left', margin: 0 }, text: '' } },
    { placeholder: { options: { name: 'title', type: 'title', x: 0.55, y: 0.6, w: 12.2, h: 0.75, fontSize: 32, bold: true, color: C.text1, valign: 'top', align: 'left', margin: 0 }, text: '' } },
  ],
  slideNumber: { x: 12.35, y: 7.05, w: 0.6, h: 0.3, fontSize: 10, color: C.accent5, align: 'right' },
});

// ── 도우미 ──
const fit = (file, box, top = false) => {
  const [iw, ih] = SIZES[path.basename(file)];
  const r = Math.min(box.w / iw, box.h / ih);
  const w = iw * r, h = ih * r;
  return { x: box.x + (box.w - w) / 2, y: top ? box.y : box.y + (box.h - h) / 2, w, h };
};
// 캡처·그림 카드: 그림자 있는 바탕 위에 비율을 지켜 넣는다
const pic = (s, file, box, name, opt = {}) => {
  const f = fit(file, box, opt.top);
  if (opt.frame !== false) {
    s.addShape(pres.shapes.RECTANGLE, { x: f.x - 0.04, y: f.y - 0.04, w: f.w + 0.08, h: f.h + 0.08, fill: { color: C.background1 }, line: { color: 'D5DDD8', width: 0.75 },
      shadow: { type: 'outer', color: '1B2A24', opacity: 0.18, blur: 6, offset: 2, angle: 90 }, objectName: name + ' 바탕' });
  }
  s.addImage({ path: file, x: f.x, y: f.y, w: f.w, h: f.h, altText: opt.alt || name, objectName: name });
  return f;
};
// 노란 메모 카드: 큰 숫자 + 설명 (앱의 메모지 모양을 따왔다)
const note = (s, x, y, w, h, big, label, opt = {}) => {
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w, h, rectRadius: 0.08, fill: { color: opt.fill || C.accent2 }, line: { type: 'none' },
    shadow: { type: 'outer', color: '1B2A24', opacity: 0.16, blur: 5, offset: 2, angle: 90 }, objectName: '메모 ' + label });
  s.addText(big, { x: x + 0.2, y: y + 0.12, w: w - 0.4, h: h * 0.55, fontSize: opt.bigSize || 34, bold: true, color: opt.color || C.text1, valign: 'bottom', margin: 0, isTextBox: true, fit: 'shrink' });
  s.addText(label, { x: x + 0.2, y: y + 0.12 + h * 0.55, w: w - 0.4, h: h * 0.45 - 0.2, fontSize: opt.labelSize || 14, color: opt.color || C.text1, valign: 'top', margin: 0, isTextBox: true });
};
const tag = (s, x, y, text, color) => {
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 1.25, h: 0.36, rectRadius: 0.06, fill: { color }, line: { type: 'none' }, objectName: '표시 ' + text });
  s.addText(text, { x, y, w: 1.25, h: 0.36, fontSize: 13, bold: true, color: C.background1, align: 'center', valign: 'middle', margin: 0, isTextBox: true });
};
const caption = (s, x, y, w, text, opt = {}) => s.addText(text, { x, y, w, h: opt.h || 0.35, fontSize: opt.size || 12, color: opt.color || C.accent5, margin: 0, valign: 'top', isTextBox: true });
const bullets = (s, x, y, w, h, items, size = 16) => s.addText(
  items.map((t, i) => ({ text: t, options: { bullet: { indent: 18 }, breakLine: i < items.length - 1, paraSpaceAfter: 8 } })),
  { x, y, w, h, fontSize: size, color: C.text1, valign: 'top', margin: 0, isTextBox: true });
const content = (section, kicker, title) => {
  const s = pres.addSlide({ masterName: 'CONTENT', sectionTitle: section });
  s.addText(kicker, { placeholder: 'kicker' });
  s.addText(title, { placeholder: 'title' });
  return s;
};

// ════════ 1. 표지 ════════
pres.addSection({ title: '소개' });
{
  const s = pres.addSlide({ masterName: 'TITLE_DARK', sectionTitle: '소개' });
  s.addText('보듬 동물병원\n예약 시스템', { placeholder: 'title' });
  s.addText('같은 앱을 세 번 옮겼다\n소스 → 컨테이너 → kubeadm → EKS (+ RDS)', { placeholder: 'body' });
  s.addText('캡스톤 발표 · 2026-11', { x: 0.7, y: 6.6, w: 6, h: 0.35, fontSize: 13, color: C.accent2, margin: 0, isTextBox: true });
  s.addShape(pres.shapes.RECTANGLE, { x: 8.51, y: 0.71, w: 4.08, h: 6.08, fill: { color: C.accent2 }, line: { type: 'none' }, objectName: '앱 화면 테두리' });
  s.addImage({ path: path.join(FIG, 'cover-intro.png'), x: 8.55, y: 0.75, w: 4.0, h: 6.0, altText: '보듬 동물병원 앱의 소개 페이지 화면', objectName: '앱 화면' });
  s.addNotes('무엇을 세 번 옮겼는지부터. 동물병원 예약 앱을 소스에서 시작해 컨테이너, EC2 의 kubeadm, EKS 로 옮겼고, 선택 과제로 DB 를 RDS 로 옮겼습니다. 모든 단계에서 같은 시나리오 테스트로 확인했고, 화면에 나오는 명령 결과는 모두 실제 터미널 캡처입니다.');
}

// ════════ 2. 워크로드 ════════
{
  const s = content('소개', '워크로드', '서비스 3개, 상태를 가진 것은 둘');
  pic(s, path.join(FIG, 'c-arch-components.png'), { x: 0.55, y: 1.55, w: 8.4, h: 3.7 }, '구성 요소 그림', { frame: false });
  note(s, 9.4, 1.6, 3.4, 1.45, '6개', '구성 요소 (web, 서비스 3, MySQL, Redis)');
  note(s, 9.4, 3.25, 3.4, 1.45, '2개', '상태를 가진 것 — 이 둘이 끝까지 한계로 남았다', { fill: C.accent6 });
  bullets(s, 0.75, 5.55, 12, 1.3, [
    'Java 21 · Spring Boot, 포트 8080, 상태 확인 /health — 설정은 모두 환경 변수',
    '서비스끼리는 부르지 않는다. 같은 MySQL(서비스마다 스키마·계정이 다름)과 Redis(로그인 세션)로만 이어진다',
  ], 15);
  s.addNotes('구성 요소는 6개입니다. web 은 Apache 로 화면과 API 경로를 나누고, 서비스 3개는 로그인, 반려동물과 공지, 예약을 맡습니다. 데이터는 MySQL 에, 로그인 세션은 Redis 에 있습니다. 이 두 개가 상태를 가진 부품이고, 발표 끝까지 이 둘이 계속 문제의 중심이 됩니다.');
}

// ════════ 3. 단계별 변화 ════════
{
  const s = content('소개', '한눈에', '같은 시나리오로 네 단계를 확인했다');
  pic(s, path.join(FIG, 'c-arch-flow.png'), { x: 0.55, y: 1.5, w: 12.2, h: 3.5 }, '단계 흐름 그림', { frame: false });
  const st = [['① jar', '60 / 60'], ['② compose', '65 / 65'], ['③ kubeadm', '65 / 65'], ['④ EKS', '65 / 65']];
  st.forEach(([k, v], i) => note(s, 0.75 + i * 3.08, 5.35, 2.8, 1.45, v, '시나리오 테스트 · ' + k, { bigSize: 30 }));
  s.addNotes('①에서 jar 를 직접 띄우고, ②에서 컨테이너로, ③에서 EC2 3대에 직접 만든 쿠버네티스로, ④에서 EKS 로 옮겼습니다. 화면이 쓰는 API 를 묶은 시나리오 테스트 하나를 모든 단계에서 그대로 돌렸고, ②부터는 화면 항목이 더해져 65개입니다. 소스는 고치지 않았습니다.');
}

// ════════ 4. ① 테스트 환경 ════════
pres.addSection({ title: '① 워크로드 테스트' });
{
  const s = content('① 워크로드 테스트', '① 워크로드 테스트 · WSL 2', '모든 단계가 쓰는 시나리오를 먼저 만들었다');
  pic(s, path.join(SHOT, '1-07-scenario.png'), { x: 5.6, y: 1.55, w: 7.2, h: 4.4 }, '시나리오 테스트 캡처', { alt: '시나리오 테스트 결과 통과 60 / 실패 0 터미널 캡처' });
  note(s, 0.55, 1.6, 4.6, 1.5, '60 / 60', '시나리오 테스트 통과 (11묶음)');
  bullets(s, 0.6, 3.4, 4.6, 3.2, [
    'WSL 2 Ubuntu · JDK 21 · Docker',
    '등록 → 조회 → 수정',
    '직원 화면, 동시 신청, 로그인 제한',
    'DB 계정 경계 9개',
    '②③④ 에서 주소만 바꿔 같은 파일로',
  ], 15);
  caption(s, 5.6, 6.1, 7.2, '실제 터미널 캡처 (2026-11-24, WSL 2)');
  s.addNotes('테스트 환경은 WSL 2 Ubuntu 입니다. 문서만 보고 같은 환경을 만들 수 있게 버전과 명령을 남겼습니다. 시나리오는 예약 등록, 조회, 수정과 직원 화면, 동시 신청, DB 계정 경계까지 60항목이고, 이후 모든 단계에서 같은 파일을 씁니다.');
}

// ════════ 5. ② 빌드 최적화 ════════
pres.addSection({ title: '② 이미지·컨테이너' });
{
  const s = content('② 이미지·컨테이너', '② 이미지 빌드 최적화', '방법을 하나씩 더하며 쟀다: 1.52GB → 366MB');
  const labels = ['A 처음', 'B +ignore', 'C +두 단계', 'D +alpine', 'E +캐시'];
  const common = {
    x: 0, y: 1.55, w: 6.0, h: 3.9, barDir: 'col', showTitle: true, titleFontSize: 15, titleColor: HEX.dk1, titleFontFace: '+mn-lt',
    showValue: true, dataLabelPosition: 'outEnd', dataLabelFontSize: 13, dataLabelColor: HEX.dk1, dataLabelFontFace: '+mn-lt',
    catAxisLabelColor: HEX.dk1, catAxisLabelFontSize: 13, catAxisLabelFontFace: '+mn-lt', valAxisHidden: true,
    valGridLine: { style: 'none' }, catGridLine: { style: 'none' }, showLegend: false, barGapWidthPct: 45,
  };
  s.addChart(pres.charts.BAR, [{ name: '이미지 크기 (MB)', labels, values: [1520, 1310, 550, 366, 366] }],
    { ...common, x: 0.55, dataLabelFormatCode: '#,##0', title: '이미지 크기 (MB)', chartColors: ['7D8C85', '7D8C85', '7D8C85', '2E7D5B', '2E7D5B'], invertedColors: undefined, objectName: '이미지 크기 차트' });
  s.addChart(pres.charts.BAR, [{ name: '한 줄 고친 뒤 재빌드 (초)', labels, values: [54.8, 46.7, 33.5, 31.4, 12.1] }],
    { ...common, x: 6.75, dataLabelFormatCode: '0.0', title: '소스 한 줄 고친 뒤 재빌드 (초)', chartColors: ['7D8C85', '7D8C85', '7D8C85', '7D8C85', '2E7D5B'], objectName: '재빌드 시간 차트' });
  note(s, 0.75, 5.7, 3.6, 1.25, '366MB', '이미지 크기 (−76%)', { bigSize: 30 });
  note(s, 4.6, 5.7, 3.6, 1.25, '12.1초', '재빌드 (−78%)', { bigSize: 30 });
  bullets(s, 8.5, 5.75, 4.4, 1.3, ['두 단계 빌드: 실행 이미지에 JRE 만', 'Gradle 캐시: 의존성 층을 다시 받지 않음'], 14);
  s.addNotes('이미지 빌드는 방법을 하나씩 더하며 같은 조건으로 쟀습니다. .dockerignore 로 빌드 맥락이 112MB 에서 7kB 로, 두 단계 빌드로 실행 이미지에 JRE 만 남겨 550MB, alpine 으로 366MB. 마지막에 Gradle 캐시를 남기자 소스 한 줄 고친 뒤 재빌드가 54.8초에서 12.1초가 됐습니다. 그래프의 값은 WSL 에서 잰 것이고, 각 단계의 캡처가 문서에 있습니다.');
}

// ════════ 6. ② 실행·배포 ════════
{
  const s = content('② 이미지·컨테이너', '② 컨테이너 실행과 배포', '6개 모두 healthy, root 가 아니고, ECR 에 올라갔다');
  pic(s, path.join(SHOT, '2-06-ps.png'), { x: 0.55, y: 1.55, w: 7.6, h: 2.6 }, 'compose ps 캡처', { alt: 'docker compose ps 결과 6개 컨테이너 healthy', top: true });
  pic(s, path.join(SHOT, '2-07-user.png'), { x: 0.55, y: 3.95, w: 7.6, h: 2.0 }, '실행 사용자 캡처', { alt: '컨테이너 6개의 실행 사용자 uid 확인', top: true });
  pic(s, path.join(SHOT, '2-13-push.png'), { x: 8.45, y: 1.55, w: 4.35, h: 1.8 }, 'ECR push 캡처', { alt: 'ECR 로 이미지 push, 계정 번호 가림', top: true });
  caption(s, 8.45, 2.85, 4.35, 'ECR push (계정 번호는 가렸다)', { size: 12 });
  note(s, 8.45, 3.4, 4.35, 1.35, '20 → 1~2건', '종료 때 끊긴 요청', { bigSize: 28 });
  note(s, 8.45, 4.95, 4.35, 1.4, '0 은 못 채움', '종료 신호를 받게 했지만 남음', { bigSize: 26, fill: C.accent6 });
  caption(s, 0.55, 5.95, 7.6, 'web 82 · 서비스 10001 · MySQL·Redis 999 — 모두 root 아님', { size: 13 });
  s.addNotes('compose 로 6개를 띄우면 healthcheck 가 모두 통과합니다. 실행 사용자는 모두 root 가 아니고, ECR 에 push 했습니다. 다 채우지 못한 기준도 있습니다. 종료 신호를 자바가 받게 고쳐서 끊기는 요청이 20건에서 1~2건으로 줄었지만 0 은 아닙니다.');
}

// ════════ 7. ③ 클러스터 구축 ════════
pres.addSection({ title: '③ 쿠버네티스' });
{
  const s = content('③ 쿠버네티스', '③ kubeadm 클러스터 구축', 'EC2 3대, 필요한 포트만 열었다');
  pic(s, path.join(FIG, 'c-arch-kubeadm.png'), { x: 0.55, y: 1.5, w: 7.0, h: 4.0 }, 'kubeadm 구성도', { frame: false });
  pic(s, path.join(SHOT, '3-01-nodes.png'), { x: 7.85, y: 1.6, w: 4.95, h: 1.1 }, '노드 Ready 캡처', { alt: 'kubectl get nodes 3대 Ready' });
  pic(s, path.join(SHOT, '3-02-sg.png'), { x: 7.85, y: 2.95, w: 4.95, h: 2.3 }, '보안 그룹 캡처', { alt: '노드 보안 그룹 규칙 5줄, IP 가림' });
  const rows = [['수업', '여기', '이유'], ['MetalLB (L2)', 'NodePort', 'VPC 에서는 L2 광고가 동작하지 않는다'], ['Calico', 'Flannel', 'Pod 끼리 통신만 필요, 부품이 적다']];
  s.addTable(rows.map((r, i) => r.map((t) => ({ text: t, options: { bold: i === 0, color: i === 0 ? C.background1 : C.text1, fill: { color: i === 0 ? C.text2 : (i % 2 ? C.background2 : C.background1) } } }))),
    { x: 0.55, y: 5.75, w: 12.25, colW: [2.6, 2.6, 7.05], fontSize: 14, border: { type: 'solid', color: 'D5DDD8', pt: 0.75 }, rowH: 0.36, margin: 0.06, objectName: '수업과 다르게 한 것' });
  s.addNotes('EC2 3대에 kubeadm 으로 컨트롤 플레인 1대, 워커 2대를 만들었습니다. 밖에서는 웹과 kubectl 포트만 이 PC 의 IP 에 열고, 노드끼리는 Flannel, API 서버, kubelet 포트만 엽니다. 수업과 다르게 한 것이 둘인데, EC2 에서는 MetalLB L2 가 동작하지 않아 NodePort 를, 네트워크 플러그인은 Flannel 을 골랐습니다.');
}

// ════════ 8. ③ 무중단 배포 ════════
{
  const s = content('③ 쿠버네티스', '③ 배포와 운영 · 같은 클러스터에서 v0 와 비교', '다시 배포 중 실패 240건 → 0건');
  tag(s, 0.55, 1.5, '문제 (v0)', C.accent3);
  pic(s, path.join(SHOT, 'prob-3-k1-rollout.png'), { x: 0.55, y: 1.95, w: 6.0, h: 2.75 }, 'v0 다시 배포 캡처', { alt: 'v0 다시 배포 중 305건 중 240건 503', top: true });
  tag(s, 6.8, 1.5, '고친 뒤', C.accent1);
  pic(s, path.join(SHOT, '3-06-ops.png'), { x: 6.8, y: 1.95, w: 6.0, h: 2.75 }, '최종 다시 배포 캡처', { alt: '최종 다시 배포 7188건 중 0건 실패', top: true });
  const fx = [['준비 전에 요청을 받음', 'startup · readiness probe'], ['복제본이 하나', '복제본 2 + maxUnavailable 0'], ['내려가는 Pod 가 요청을 끊음', 'preStop 으로 잠깐 기다림']];
  fx.forEach(([a, b], i) => {
    const x = 0.55 + i * 4.15;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: 5.0, w: 3.95, h: 1.15, rectRadius: 0.08, fill: { color: C.background2 }, line: { type: 'none' }, objectName: '원인 ' + (i + 1) });
    s.addText([{ text: a, options: { color: C.accent3, bold: true, breakLine: true } }, { text: '→ ' + b, options: { color: C.text2, bold: true } }],
      { x: x + 0.2, y: 5.05, w: 3.6, h: 1.05, fontSize: 15, valign: 'middle', margin: 0, isTextBox: true });
  });
  caption(s, 0.55, 6.35, 12.25, '업데이트·롤백은 125건 → 2건. 남은 2건은 응답 코드가 아닌 연결 끊김이고 원인을 찾지 못했다 (같은 파일로 EKS 에서는 0건)', { size: 13, color: C.text1, h: 0.6 });
  s.addNotes('가장 단순한 배포 v0 를 같은 클러스터에 띄우고 요청을 계속 보내며 다시 배포했더니 305건 중 240건이 503 이었습니다. 원인은 셋이 겹쳐 있었습니다. probe, 복제본 2개와 maxUnavailable 0, preStop 을 모두 넣자 7천여 건 중 0건. 업데이트·롤백은 125건에서 2건까지 줄었는데, 남은 2건은 연결 끊김이고 원인을 찾지 못했다고 문서에 밝혔습니다.');
}

// ════════ 9. ③ 데이터·설정 ════════
{
  const s = content('③ 쿠버네티스', '③ 데이터와 설정', 'MySQL Pod 를 지워도 예약이 남는다');
  tag(s, 0.55, 1.5, '문제 (v0)', C.accent3);
  pic(s, path.join(SHOT, 'prob-3-k2-data-lost.png'), { x: 0.55, y: 1.95, w: 6.0, h: 1.4 }, 'v0 데이터 사라짐 캡처', { alt: 'v0 MySQL Pod 삭제 뒤 예약 176 없음', top: true });
  tag(s, 6.8, 1.5, '고친 뒤', C.accent1);
  pic(s, path.join(SHOT, '3-10-db-replace.png'), { x: 6.8, y: 1.95, w: 6.0, h: 1.4 }, '최종 데이터 유지 캡처', { alt: 'MySQL Pod 삭제 뒤에도 예약 217 남음', top: true });
  note(s, 0.55, 3.75, 3.9, 1.55, '176 사라짐', 'v0: 볼륨 없는 Deployment', { bigSize: 28, fill: C.accent6 });
  note(s, 4.7, 3.75, 3.9, 1.55, '217 유지', 'StatefulSet + 볼륨 (워커1 디스크)', { bigSize: 28 });
  note(s, 8.85, 3.75, 3.95, 1.55, '16줄 → 0줄', '배포 정보에 보이던 비밀번호', { bigSize: 28 });
  bullets(s, 0.6, 5.65, 12.2, 1.2, [
    '설정은 ConfigMap, 비밀번호는 Secret — kubectl get deploy -o yaml 에 값이 나오지 않는다',
    '교체하는 동안은 DB 요청이 11초 실패했다 (26건). DB 가 하나뿐인 구성의 한계',
  ], 15);
  s.addNotes('v0 는 MySQL 을 볼륨 없이 띄워서 Pod 를 지우자 예약 176번이 사라졌습니다. StatefulSet 과 볼륨으로 바꾼 뒤에는 217번이 남았습니다. 비밀번호는 v0 에서 배포 정보에 16줄 그대로 보였고, Secret 으로 옮겨 0줄이 됐습니다. 다만 교체하는 11초 동안은 DB 요청이 실패합니다.');
}

// ════════ 10. ③ 노드 장애 ════════
{
  const s = content('③ 쿠버네티스', '③ 노드 장애에서 배운 것', '기본값은 "오래 기다리기"였다: 393초 → 115초');
  pic(s, path.join(FIG, 'c-node-failure-timeline.png'), { x: 0.55, y: 1.5, w: 8.3, h: 2.5 }, '노드 장애 타임라인', { frame: false });
  note(s, 9.15, 1.55, 3.65, 1.2, '393 → 115초', '앱만 있는 워커가 죽은 뒤 전부 복구', { bigSize: 26 });
  note(s, 9.15, 2.95, 3.65, 1.2, '675 → 110건', '그동안 실패한 요청', { bigSize: 26 });
  const items = [
    ['K-9', '노드가 죽어도 300초 동안 Pod 를 옮기지 않음', 'tolerationSeconds 30'],
    ['K-10', '클러스터 DNS 둘이 한 노드에 → 그 노드와 함께 모든 요청 실패', 'CoreDNS 를 두 노드에 나눔'],
    ['K-11', 'DB 가 있는 노드가 죽으면 DB 가 옮겨 가지 못함', '한계로 남김 → 선택 과제 RDS'],
  ];
  items.forEach(([k, a, b], i) => {
    const y = 4.45 + i * 0.82;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 0.55, y, w: 12.25, h: 0.7, rectRadius: 0.06, fill: { color: i === 2 ? 'FBE9E7' : C.background2 }, line: { type: 'none' }, objectName: '노드 장애 ' + k });
    s.addText(k, { x: 0.75, y, w: 0.9, h: 0.7, fontSize: 15, bold: true, color: i === 2 ? C.accent3 : C.accent1, valign: 'middle', margin: 0, isTextBox: true });
    s.addText(a, { x: 1.7, y, w: 6.9, h: 0.7, fontSize: 15, color: C.text1, valign: 'middle', margin: 0, isTextBox: true });
    s.addText(b, { x: 8.7, y, w: 4.0, h: 0.7, fontSize: 15, bold: true, color: C.text2, valign: 'middle', margin: 0, isTextBox: true });
  });
  caption(s, 0.55, 6.95, 9, '타임라인은 2026-11-23 측정 기록으로 그린 것이다 (③ 6.4)');
  s.addNotes('워커를 강제로 멈추자 쿠버네티스는 기본값대로 300초를 기다린 뒤에야 Pod 를 옮겨서, 393초 동안 로그인이 안 됐습니다. 대기 시간을 30초로 줄여 115초에 전부 복구됐습니다. 클러스터 DNS 가 한 노드에 몰려 있던 문제도 이 실험에서 찾았습니다. DB 가 있는 노드가 죽으면 DB 가 옮겨 가지 못하는 것은 한계로 남겼고, 선택 과제의 RDS 가 이것을 풉니다.');
}

// ════════ 11. ④ EKS 전환 ════════
pres.addSection({ title: '④ EKS' });
{
  const s = content('④ EKS', '④ EKS 전환 · Auto Mode', 'EKS 가 대신한 일과 내가 정해야 했던 일');
  const rows = [
    ['', 'kubeadm (③)', 'EKS Auto Mode (④)'],
    ['컨트롤 플레인·노드', '직접 init · join, 2대 고정', 'EKS 가 운영, 노드도 자동'],
    ['이미지 받기', 'ECR 로그인 Secret, 12시간', '노드 IAM 역할 — 할 일 없음'],
    ['밖으로', 'NodePort 30080', 'Ingress → ALB (IngressClass 는 직접)'],
    ['MySQL 볼륨', '워커1 디스크를 PV 로 직접 등록', 'EBS gp3 (StorageClass 는 직접)'],
    ['노드 분산', 'maxSkew 1', '+ minDomains 2, 가용 영역 분산'],
  ];
  s.addTable(rows.map((r, i) => r.map((t, j) => ({ text: t, options: {
    bold: i === 0 || j === 0, color: i === 0 ? C.background1 : C.text1,
    fill: { color: i === 0 ? C.text2 : (j === 2 ? 'E3F1EA' : (i % 2 ? C.background2 : C.background1)) } } }))),
    { x: 0.55, y: 1.55, w: 8.6, colW: [2.1, 3.0, 3.5], fontSize: 14, rowH: 0.62, valign: 'middle', border: { type: 'solid', color: 'D5DDD8', pt: 0.75 }, margin: 0.08, objectName: 'kubeadm 과 EKS 비교' });
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 9.45, y: 1.55, w: 3.35, h: 3.75, rectRadius: 0.08, fill: { color: C.text2 }, line: { type: 'none' }, objectName: '직접 정한 것 카드' });
  s.addText([
    { text: '그래도 직접 정한 것', options: { bold: true, color: C.accent2, fontSize: 17, breakLine: true } },
    { text: 'StorageClass (E-2)', options: { bullet: true, breakLine: true } },
    { text: 'IngressClass (E-1)', options: { bullet: true, breakLine: true } },
    { text: '노드·영역 분산 (E-3)', options: { bullet: true, breakLine: true } },
    { text: '정리에서 뺄 Pod (E-4)', options: { bullet: true, breakLine: true } },
    { text: ' ', options: { breakLine: true } },
    { text: '대신 할 수 없게 된 것', options: { bold: true, color: C.accent2, fontSize: 17, breakLine: true } },
    { text: '노드를 멈추는 장애 실험', options: { bullet: true } },
  ], { x: 9.7, y: 1.75, w: 2.95, h: 3.4, fontSize: 15, color: C.background1, valign: 'top', margin: 0, paraSpaceAfter: 8, isTextBox: true });
  bullets(s, 0.6, 5.55, 12.2, 1.3, [
    'E-3: Auto Mode 가 노드를 줄이며 Pod 를 한 노드에 몰았다 → minDomains 2 로 둘째 복제본이 같은 노드에 못 가게',
    'E-4: MySQL·Redis 를 지키려는 표시 때문에 노드가 24시간 안 지워진다 → 맞바꿈, 노드를 바꿀 때 사람이 옮긴다',
  ], 15);
  s.addNotes('EKS 는 컨트롤 플레인과 노드, 이미지 로그인, 로드밸런서와 볼륨 드라이버를 대신해 줍니다. 그래도 StorageClass, IngressClass, 분산 규칙, 정리 예외는 제가 정해야 했고, 그중 둘은 Auto Mode 의 노드 정리 동작 때문에 새로 생긴 문제였습니다.');
}

// ════════ 12. ④ 노출·데이터 ════════
{
  const s = content('④ EKS', '④ 노출과 데이터', 'ALB 로 열고, 볼륨은 StorageClass 를 직접 만들었다');
  pic(s, path.join(FIG, 'c-arch-eks.png'), { x: 0.55, y: 1.5, w: 6.3, h: 3.6 }, 'EKS 구성도', { frame: false });
  tag(s, 7.15, 1.5, '문제', C.accent3);
  pic(s, path.join(SHOT, 'prob-4-e2-gp2.png'), { x: 7.15, y: 1.92, w: 5.65, h: 2.1 }, 'gp2 Pending 캡처', { alt: '기본 gp2 로 만든 PVC 가 Pending, 드라이버 이름이 다름' });
  tag(s, 7.15, 4.25, '고친 뒤', C.accent1);
  pic(s, path.join(SHOT, '4-03-storage.png'), { x: 7.15, y: 4.67, w: 5.65, h: 1.6 }, 'StorageClass 캡처', { alt: 'vet2-ebs StorageClass, PVC Bound 2Gi' });
  note(s, 0.55, 5.35, 3.1, 1.45, '65 / 65', 'ALB 를 거친 시나리오', { bigSize: 28 });
  note(s, 3.8, 5.35, 3.1, 1.45, '0 / 9,700', '다시 배포 중 실패', { bigSize: 28 });
  caption(s, 7.15, 6.45, 5.65, '기본 gp2 는 ebs.csi.aws.com 을 기다리지만 Auto Mode 의 드라이버는 ebs.csi.eks.amazonaws.com', { size: 12, h: 0.5 });
  s.addNotes('밖으로는 Ingress 하나로 ALB 를 만들고, Pod IP 로 바로 보내며 이 PC 의 IP 에서만 받게 했습니다. 볼륨은 클러스터에 처음부터 있는 gp2 로는 영영 만들어지지 않았습니다. 기다리는 드라이버 이름과 Auto Mode 의 드라이버 이름이 달라서입니다. gp3 StorageClass 를 직접 만들어 해결했고, MySQL Pod 를 지워도 예약이 남았습니다. 다시 배포, 업데이트·롤백 모두 실패 0건이었습니다.');
}

// ════════ 13. 선택 과제 RDS ════════
pres.addSection({ title: '선택 과제·회고' });
{
  const s = content('선택 과제·회고', '선택 과제 · RDS', 'DB 를 클러스터 밖으로: 실패 372건 → 39건');
  pic(s, path.join(FIG, 'c-arch-rds.png'), { x: 0.55, y: 1.5, w: 6.4, h: 3.2 }, 'RDS 구성도', { frame: false });
  pic(s, path.join(SHOT, '6-12-node-w1.png'), { x: 7.2, y: 1.55, w: 5.6, h: 4.15 }, '워커 정지 캡처', { alt: 'DB 가 있는 워커를 멈췄을 때 필수 구성 372건, RDS 구성 39건 실패' });
  note(s, 0.55, 4.95, 3.1, 1.6, '372건', '클러스터 안 MySQL\n약 1,000건 중', { bigSize: 30, fill: C.accent6 });
  note(s, 3.85, 4.95, 3.1, 1.6, '39건', 'RDS 구성 (같은 시간)\n약 13,800건 중', { bigSize: 30 });
  caption(s, 0.55, 6.7, 6.4, 'DB 가 있는 워커(vet2-w1)를 강제로 멈췄을 때', { size: 12 });
  caption(s, 7.2, 5.9, 5.6, '사설 서브넷 · 두 노드 보안 그룹에서만 3306 · 연결 한도 60 → 서비스당 연결 3개 · 재시작 뒤 예약 유지', { size: 12, h: 0.75, color: C.text1 });
  s.addNotes('선택 과제로 같은 클러스터에 RDS 를 쓰는 구성을 하나 더 띄웠습니다. 사설 서브넷에 두고 두 클러스터의 노드 보안 그룹에서만 3306 을 받습니다. DB 가 있는 워커를 강제로 멈추고 두 구성에 같은 시간에 요청을 보냈더니, 클러스터 안 MySQL 구성은 372건이 실패하며 끝까지 회복하지 못했고, RDS 구성은 39건이었습니다. 연결 한도 60 을 넘는 문제는 서비스당 연결 수를 3으로 줄여 풀었습니다.');
}

// ════════ 14. 선택 과제 + 회고 ════════
{
  const s = content('선택 과제·회고', '선택 과제와 회고', '관리형은 설치를 없애 주지만, 동작을 정하는 일은 남긴다');
  const rows = [
    ['선택 과제', '결과'],
    ['빌드 최적화', '1.52GB → 366MB, 재빌드 54.8초 → 12.1초'],
    ['무중단 롤링 업데이트', '③ 240 → 0건, ④ 0 / 9,700'],
    ['Kustomize', 'base + overlay 5개 + component 1개'],
    ['요청·분산·PDB', '노드를 비울 때 PDB 가 마지막 복제본을 지킴'],
    ['가용 영역 분산', '노드 2a, 2c (minDomains 2)'],
    ['RDS', '사설 서브넷, 두 클러스터 65 / 65'],
    ['Secrets Manager', '일부 — RDS 관리자 비밀번호만'],
  ];
  s.addTable(rows.map((r, i) => r.map((t, j) => ({ text: t, options: { bold: i === 0 || j === 0, color: i === 0 ? C.background1 : C.text1, fill: { color: i === 0 ? C.text2 : (i % 2 ? C.background2 : C.background1) } } }))),
    { x: 0.55, y: 1.55, w: 6.9, colW: [2.4, 4.5], fontSize: 14, rowH: 0.52, valign: 'middle', border: { type: 'solid', color: 'D5DDD8', pt: 0.75 }, margin: 0.08, objectName: '선택 과제 표' });
  const cmp = [
    ['kubeadm', '모든 부품이 보이고 고칠 수 있다. 장애 실험과 대기 시간 조정이 됐다. 볼륨·노출·로그인은 손으로 했다'],
    ['EKS', '설치와 연결이 사라졌다. 대신 노드 정리가 새 문제 둘(E-3, E-4)을 만들었고, 노드를 멈출 수 없다'],
  ];
  cmp.forEach(([k, t], i) => {
    const y = 1.55 + i * 1.6;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 7.75, y, w: 5.05, h: 1.4, rectRadius: 0.08, fill: { color: i ? 'E3F1EA' : C.background2 }, line: { type: 'none' }, objectName: '회고 ' + k });
    s.addText([{ text: k, options: { bold: true, color: C.text2, fontSize: 17, breakLine: true } }, { text: t, options: { color: C.text1, fontSize: 14 } }],
      { x: 7.95, y: y + 0.12, w: 4.7, h: 1.2, valign: 'top', margin: 0, paraSpaceAfter: 4, isTextBox: true });
  });
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 7.75, y: 4.85, w: 5.05, h: 1.55, rectRadius: 0.08, fill: { color: C.text2 }, line: { type: 'none' }, objectName: '회고 한 줄' });
  s.addText('배울 때는 kubeadm 이 더 잘 보였고,\n운영한다면 EKS 가 할 일을 줄인다', { x: 7.95, y: 4.95, w: 4.7, h: 1.35, fontSize: 15, bold: true, color: C.background1, valign: 'middle', margin: 0, isTextBox: true });
  caption(s, 0.55, 6.6, 7.0, '하지 않은 것: Helm, Gateway API, HTTPS, HPA', { size: 13, h: 0.4 });
  s.addNotes('선택 과제는 표와 같습니다. Secrets Manager 는 RDS 관리자 비밀번호에만 썼습니다. 회고로, 직접 만든 kubeadm 은 손이 많이 가지만 무엇이 일어나는지 다 보였고, EKS 는 설치와 연결을 없애 주지만 동작을 정하는 일은 남겼습니다. 오히려 관리형이 대신 해 주는 노드 정리 때문에 새 문제가 둘 생겼습니다.');
}

// ════════ 15. 시연 + 비용·정리 ════════
pres.addSection({ title: '시연·정리' });
{
  const s = content('시연·정리', '시연 · ALB 주소로 등록 → 조회 → 수정 → 승인', '시연과 비용·정리');
  const cover = 'image/png;base64,' + fs.readFileSync(path.join(FIG, 'video-cover.png')).toString('base64');
  s.addMedia({ type: 'video', path: path.resolve(__dirname, '../../docs/video/시연-EKS.mp4'), cover, x: 0.55, y: 1.55, w: 7.2, h: 4.05, objectName: '시연 영상' });
  caption(s, 0.55, 5.7, 7.2, '실제 녹화 (1분 54초) — 시연이 안 될 때 이 영상을 튼다', { size: 13 });
  const rows = [['자원', '시간당'], ['EC2 t3.medium × 3 (③)', '0.16달러'], ['EKS 컨트롤 플레인 + 노드 2', '0.27달러 + 수수료'], ['ALB 2개', '약 0.06달러'], ['RDS db.t4g.micro', '0.025달러'], ['합계', '약 0.55달러']];
  s.addTable(rows.map((r, i) => r.map((t) => ({ text: t, options: { bold: i === 0 || i === rows.length - 1, color: i === 0 ? C.background1 : C.text1, fill: { color: i === 0 ? C.text2 : (i === rows.length - 1 ? 'FCEFC7' : (i % 2 ? C.background2 : C.background1)) } } }))),
    { x: 8.05, y: 1.55, w: 4.75, colW: [2.95, 1.8], fontSize: 14, rowH: 0.42, valign: 'middle', border: { type: 'solid', color: 'D5DDD8', pt: 0.75 }, margin: 0.08, objectName: '비용 표' });
  s.addText([
    { text: '지우는 순서', options: { bold: true, color: C.text2, breakLine: true } },
    { text: 'stacks.sh down all', options: { fontFace: 'Courier New', bold: true, breakLine: true } },
    { text: 'RDS → EKS 안의 Ingress·PVC(ALB·EBS) → EKS → kubeadm → ECR → 네트워크', options: { color: C.text1 } },
  ], { x: 8.05, y: 4.3, w: 4.75, h: 1.9, fontSize: 14, valign: 'top', margin: 0, paraSpaceAfter: 6, isTextBox: true });
  s.addNotes('ALB 주소로 보호자 로그인, 예약 등록, 조회, 시간 변경을 하고, 간호사로 승인하면 화면 아래에 응답한 Pod 이름이 보입니다. 다시 보호자로 들어가면 예약 확정으로 바뀝니다. 비용은 모두 켜 두면 시간당 약 0.55달러이고, 발표가 끝나면 스택 스크립트 하나로 의존 순서대로 지웁니다. 스택 밖에 생긴 ALB 와 EBS 를 먼저 지우는 것까지 스크립트가 합니다.');
}

// ════════ 16. 예비: 완성 기준 점검표 ════════
pres.addSection({ title: '예비' });
{
  const s = content('예비', '예비 슬라이드 · 질의응답용', '완성 기준 점검표');
  const rows = [
    ['단계', '기준', '결과'],
    ['①', 'WSL 2 빌드·실행, 시나리오', '빌드 성공, /health 200, 60 / 60'],
    ['②', '이미지·compose, root 아님', '6개 healthy, 65 / 65, 모두 root 아님'],
    ['②', '종료 신호에 요청을 마침', '1~2건 남음 — 0 은 못 채움'],
    ['③', 'kubeadm 3대, 필요한 포트만', '3대 Ready, 보안 그룹 5줄'],
    ['③', '롤링 업데이트·롤백', '다시 배포 0건, 업데이트·롤백 2건 — 0 은 못 채움'],
    ['③', 'DB Pod 교체 뒤 데이터, Secret', '예약 217 유지, 비밀번호 0줄'],
    ['④', 'ALB, StorageClass, 시나리오', 'ALB · vet2-ebs · 65 / 65'],
    ['④', '무중단·자동 복구·데이터', '모두 실패 0건, 예약 204·207 유지'],
  ];
  s.addTable(rows.map((r, i) => r.map((t, j) => ({ text: t, options: { bold: i === 0, color: i === 0 ? C.background1 : (/못 채움/.test(t) ? C.accent3 : C.text1), fill: { color: i === 0 ? C.text2 : (i % 2 ? C.background2 : C.background1) }, align: j === 0 ? 'center' : 'left' } }))),
    { x: 0.55, y: 1.55, w: 12.25, colW: [0.9, 4.6, 6.75], fontSize: 14, rowH: 0.52, valign: 'middle', border: { type: 'solid', color: 'D5DDD8', pt: 0.75 }, margin: 0.08, objectName: '완성 기준 점검표' });
  caption(s, 0.55, 6.45, 12.25, '근거: v2/docs/5-최종문서.md 0.3 — 기준마다 단계별 문서의 절과 캡처를 가리킨다', { size: 12 });
  s.addNotes('질문이 나오면 쓰는 슬라이드입니다. 다 채우지 못한 기준은 두 개이고, 문서에 그렇게 적었습니다.');
}

(async () => {
  await pres.writeFile({ fileName: OUT });
  await applyTheme(OUT, THEME);
  console.log('저장:', OUT);
})();
