---
name: 보듬 동물병원 — 병원 게시판
description: 초록 펠트 판 위에 종이 쪽지를 압정으로 꽂은 홈 화면의 시각 체계
colors:
  felt: "#1f5d45"
  felt-deep: "#143d2e"
  ink: "#161616"
  ink-soft: "#3d3d3a"
  pink: "#f4b8c5"
  manila: "#ecd98f"
  paper: "#ecece6"
  red: "#b3261e"
  chalk: "#f4f6f1"
typography:
  display:
    fontFamily: '"Black Han Sans", "Pretendard Variable", Pretendard, sans-serif'
    fontSize: "clamp(3rem, 7.4vw, 6rem)"
    fontWeight: 400
    lineHeight: 1.04
    letterSpacing: "0"
  headline:
    fontFamily: '"Black Han Sans", "Pretendard Variable", Pretendard, sans-serif'
    fontSize: "clamp(1.75rem, 3.4vw, 2.5rem)"
    fontWeight: 400
    lineHeight: 1.15
    letterSpacing: "0"
  headline-serif:
    fontFamily: '"Nanum Myeongjo", "Noto Serif KR", serif'
    fontSize: "clamp(1.875rem, 4vw, 3rem)"
    fontWeight: 800
    lineHeight: 1.3
    letterSpacing: "-0.02em"
  numeral:
    fontFamily: '"Black Han Sans", "Pretendard Variable", Pretendard, sans-serif'
    fontSize: "4.5rem"
    fontWeight: 400
    lineHeight: 1
  title:
    fontFamily: '"Black Han Sans", "Pretendard Variable", Pretendard, sans-serif'
    fontSize: "2.125rem"
    fontWeight: 400
    lineHeight: 1.15
  title-serif:
    fontFamily: '"Nanum Myeongjo", "Noto Serif KR", serif'
    fontSize: "1.375rem"
    fontWeight: 800
    lineHeight: 1.35
  sign:
    fontFamily: '"Do Hyeon", "Pretendard Variable", Pretendard, sans-serif'
    fontSize: "1.375rem"
    fontWeight: 400
    lineHeight: 1.2
  body:
    fontFamily: '"Pretendard Variable", Pretendard, -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Malgun Gothic", "맑은 고딕", system-ui, sans-serif'
    fontSize: "17px"
    lineHeight: 1.7
  body-serif:
    fontFamily: '"Nanum Myeongjo", "Noto Serif KR", serif'
    fontSize: "16px"
    fontWeight: 700
    lineHeight: 1.85
  mono:
    fontFamily: '"Nanum Gothic Coding", ui-monospace, Consolas, monospace'
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: '"Nanum Gothic Coding", ui-monospace, Consolas, monospace'
    fontSize: "14px"
    fontWeight: 700
rounded:
  none: "0"
  round: "50%"
spacing:
  gutter: "24px"
  head-gap: "40px"
  section: "clamp(72px, 9vw, 120px)"
components:
  button-ink:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.pink}"
    typography: "{typography.sign}"
    rounded: "{rounded.none}"
    padding: "0 26px"
    height: "56px"
  button-line:
    textColor: "{colors.ink}"
    typography: "{typography.sign}"
    rounded: "{rounded.none}"
    padding: "0 26px"
    height: "56px"
  button-line-hover:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.pink}"
  section-title:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.headline}"
    rounded: "{rounded.none}"
    padding: "10px 20px 8px"
  ticket:
    backgroundColor: "{colors.pink}"
    textColor: "{colors.ink}"
    rounded: "{rounded.none}"
    padding: "52px 44px 44px 48px"
  receipt:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.mono}"
    rounded: "{rounded.none}"
    padding: "40px 22px 34px"
    width: "316px"
  receipt-row-now:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
  tag:
    backgroundColor: "{colors.manila}"
    textColor: "{colors.ink}"
    padding: "18px 30px 18px 58px"
  nav-tab:
    backgroundColor: "{colors.manila}"
    textColor: "{colors.ink}"
    rounded: "{rounded.none}"
    padding: "8px 16px"
  badge:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.label}"
    rounded: "{rounded.none}"
    padding: "3px 10px"
  stamp:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.red}"
    rounded: "{rounded.round}"
    size: "132px"
---

# Design System: 보듬 동물병원 — 병원 게시판

> 적용 범위: 이 문서는 홈 화면(`web/site/pages/index.html`)에 구현된 체계를 기록한다. 토큰과 공통 머리말·바닥글·딱지는 `web/site/assets/css/board-shell.css`의 `body.board` 범위에 있고, 홈 전용 부품은 `board.css`에 있다. 병원 소개·의료진·진료 안내·공지사항 네 페이지도 같은 세계로 옮겼다(`body.board.board-page`). 이 페이지들은 기존 마크업을 그대로 두고 `web/site/assets/css/board-pages.css`에서 같은 토큰으로 종이 쪽지를 입혔으며, 글꼴과 `board-shell.css`, `board.css`는 `partials/head.html`에서 모든 소개 페이지에 불러온다. 아래 부품 기록은 홈에서 뽑은 것이고, 하위 페이지 전용 부품(페이지 머리 표 딱지, 탭 꼬리표, 공지 표, 자주 묻는 질문 색인 카드)은 `board-pages.css`가 기준이다. 하위 네 페이지는 마감 리뷰를 거치지 않았다. `web/app`의 보호자 예약 화면(로그인, 예약 홈, 예약하기, 내 예약, 내 반려동물)도 같은 세계를 쓴다. `app/src/main.tsx`가 `board-shell.css`를 불러오고 `app/src/board-app.css`가 기존 부품을 입히며, `App.tsx`가 보호자 화면에서만 `body.board`를 켠다. 일하는 화면이라 쪽지를 기울이지 않고(제목 띠·탭·예약권만 기운다), 선택 상태는 마닐라 채움과 잉크 반전, 지남·마감·휴진은 빗금으로 나타낸다. 예약 화면도 마감 리뷰를 거치지 않았다. 간호사·원장 화면은 별도의 EMR 체계(`app/src/emr/emr.css`)를 그대로 쓰며 이 문서의 범위 밖이다.

## Overview

**Creative North Star: "병원 게시판"**

홈은 병원 접수대 옆에 걸린 게시판이다. 초록 펠트 판이 바닥이고, 그 위에 서로 다른 종이 쪽지가 빨간 압정으로 꽂혀 있다. 가장 큰 쪽지는 분홍 예약권이고, 진료 시간은 영수증 띠, 전화번호는 마닐라 꼬리표, 원칙은 신문 오림, 의료진은 명함, 예약 방법은 절취선으로 이어진 번호표다. 정보마다 종이의 종류가 다르고, 종이마다 활자가 다르다. 같은 카드를 줄 세우는 병원 템플릿과 반대 방향에 있다.

재료는 좁게 묶여 있다. 종이는 세 가지(분홍, 마닐라, 신문지색), 잉크는 검정 하나, 도장은 빨강 하나다. 색을 더 늘리지 않고, 농담이 필요한 자리는 빗금과 점선으로 낸다. 사진과 일러스트는 어디에도 없다. 화면은 글자, 색, 실제 정보(진료 시간, 의료진, 진료 항목, 공지)로만 채운다.

움직임은 부드럽지 않다. 모든 전환이 `steps(2, end)`로 두 번 끊어져서, 종이를 손으로 집었다 놓는 느낌을 낸다. 공들인 장면은 하나뿐이다. 첫 화면의 예약권에 포인터나 포커스가 닿으면 예약권이 똑바로 들리고 주변 쪽지가 한 칸씩 비켜난다.

**Key Characteristics:**
- 초록 펠트 판 위의 종이 콜라주. 쪽지는 압정으로 꽂히고 조금씩 기운다.
- 종이 세 가지, 검은 잉크, 빨간 도장. 그 밖의 색은 쓰지 않는다.
- 농담은 135도 빗금과 점선으로 낸다. 회색 단계를 만들지 않는다.
- 활자는 종이의 종류를 따른다. 포스터 고딕, 간판체, 명조, 영수증 고정폭.
- 모서리는 직각이다. 원은 압정, 도장, 절취 홈에만 쓴다.
- 가장자리는 절취선(굵은 점선)이나 톱니로 끝난다.
- 움직임은 두 단계 `steps()`만 쓴다.
- 사진과 일러스트 없음.

## Colors

초록 판 하나, 종이 셋, 잉크 하나, 도장 하나로 이루어진 팔레트다. 값은 frontmatter가 기준이다.

### Primary
- **표 딱지 분홍** (`pink`): 예약권의 종이 색이고, 검은 버튼 위 글자색이다. 「예약」과 직접 이어지는 자리에만 쓴다. 첫 화면과 마지막의 예약권, 머리의 「온라인 예약」 탭, 좁은 화면 고정 바의 예약 버튼, 그리고 진료 과목 카드 한 장과 원칙 옆 메모 한 장.

### Secondary
- **마닐라 꼬리표** (`manila`): 안내와 길잡이의 종이. 전화 꼬리표, 메뉴 탭, 「자세히 보기」 딱지, 번호표 띠, 오시는 길 꼬리표, 겹친 카드 묶음에서 한 장.

### Tertiary
- **도장 빨강** (`red`): 압정 머리, 「일요일 휴진」 도장의 테두리와 글자, 이벤트 배지, 링크에 포인터가 닿았을 때의 밑줄과 글자. 면으로 넓게 칠하지 않는다.

### Neutral
- **펠트 초록** (`felt`): 본문 판. 5px 간격의 흰 점(불투명도 0.045)이 깔려 천의 결을 낸다. 머리 줄의 바탕이기도 하다.
- **깊은 펠트** (`felt-deep`): 맨 위 안내 줄, 바닥글, 좁은 화면의 고정 바, 본문 아래로 남는 여백.
- **잉크 검정** (`ink`): 종이 위의 모든 글자, 테두리, 점선, 섹션 제목 띠의 바탕, 영수증의 「지금」 줄 바탕.
- **옅은 잉크** (`ink-soft`): 종이 위 보조 글자(날짜, 꼬리표의 작은 이름, 경력, 지난 시간). 세 종이 모두에서 명암비 7:1 이상이 되도록 고른 값이다.
- **신문지색** (`paper`): 영수증, 신문 오림, 공지 오림, 명함, 이름표, 도장 딱지의 종이. 검은 띠 위 글자색으로도 쓴다.
- **분필 흰색** (`chalk`): 판 위에 직접 닿는 것에만 쓴다. 판 위 요소의 포커스 테두리, 그리고 머리·바닥글·고정 바의 경계선(불투명도 0.28).

### Named Rules
**세 종이 규칙.** 쪽지의 바탕은 분홍, 마닐라, 신문지색 셋 중 하나다. 네 번째 종이 색을 만들지 않는다. 한 묶음 안에서 구분이 필요하면 종이를 바꾸거나 기울기와 압정 위치를 바꾼다.

**빗금 규칙.** 지난 시간과 점심 줄처럼 한 단계 물러나야 하는 자리는 135도 빗금(`--hatch`, 5px 간격에 1px 잉크 선, 불투명도 0.17)을 깔고 글자를 옅은 잉크로 바꾼다. 회색 면이나 투명도로 낮추지 않는다. 구분선도 색을 바꾸지 않고 실선과 점선의 차이로 나눈다.

**도장 규칙.** 빨강은 찍히거나 꽂힌 것에만 쓴다. 종이 바탕이나 버튼 바탕으로 쓰지 않는다. 예외는 이벤트 배지 하나다.

## Typography

**Display Font:** Black Han Sans (대체: Pretendard Variable)
**Sign Font:** Do Hyeon (대체: Pretendard Variable)
**Serif Font:** Nanum Myeongjo 700/800 (대체: Noto Serif KR)
**Label/Mono Font:** Nanum Gothic Coding 400/700 (대체: ui-monospace, Consolas)
**Body Font:** Pretendard Variable (공통 `head` 조각에서 불러오는 `--font`)

**Character:** 게시판에 붙은 종이는 저마다 다른 곳에서 인쇄되었다. 예약권과 번호는 굵은 포스터 고딕, 버튼과 탭은 간판체, 신문 오림과 명함은 명조, 영수증과 날짜는 고정폭이다. 긴 설명 문장만 Pretendard로 조용히 읽힌다.

네 가지 한글 활자는 프로젝트에서 직접 서빙한다. 파일은 `web/site/assets/fonts/<글꼴>/`(Fontsource 5.3.0의 woff2 조각, SIL OFL 1.1, 글꼴마다 `LICENSE.txt` 동봉)에 있고 `web/site/assets/css/fonts.css`가 `unicode-range`로 나눠 선언한다(`font-display: swap`). 소개 페이지는 `partials/head.html`에서, 예약 앱은 `app/index.html`에서 같은 파일을 불러온다. 본문용 Pretendard는 여전히 jsDelivr CDN에서 온다.

### Hierarchy
- **Display** (400, `clamp(3rem, 7.4vw, 6rem)`, 1.04): 첫 화면 예약권의 제목 하나. 마지막 예약권은 같은 활자를 `clamp(2rem, 4.4vw, 3.25rem)`, 1.15로 줄여 쓴다.
- **Headline** (400, `clamp(1.75rem, 3.4vw, 2.5rem)`, 1.15): 검은 띠에 담기는 섹션 제목, 전화 꼬리표의 번호.
- **Headline Serif** (800, `clamp(1.875rem, 4vw, 3rem)`, 1.3, 자간 -0.02em): 신문 오림의 머리기사.
- **Numeral** (400, 4.5rem, 1): 번호표의 01–04. 640px 이하에서는 3.5rem.
- **Title** (400, 2.125rem, 1.15): 진료 과목 카드의 이름. 묶음의 첫 장은 2.75rem으로 키운다.
- **Title Serif** (800, 1.375rem–2.125rem): 공지 제목, 명함의 이름. 명함 묶음의 첫 장은 2.875rem.
- **Sign** (400, 1.125rem–1.75rem, 줄 높이 1–1.4): 버튼(1.375rem), 링크(1.1875rem), 메뉴 탭(19px), 예약권 꼬리표의 값(1.75rem), 영수증 제목(1.625rem), 번호표 단계 이름(1.5rem), 메모(1.375rem).
- **Body** (17px, 1.7): 쪽지 안의 설명 문장. 640px 이하에서는 16px. 쪽지 안 목록은 16px에 굵기 600.
- **Body Serif** (700, 16px, 1.85): 신문 오림의 단 본문, 명함의 한마디.
- **Mono** (400/700, 15px, 1.5): 영수증의 줄. 숫자는 `tabular-nums`.
- **Label** (700, 14px): 꼬리표의 작은 이름, 날짜, 직함, 배지. 대문자 변환이나 넓은 자간을 쓰지 않는다.

### Named Rules
**종이가 활자를 정한다 규칙.** 활자는 글의 중요도가 아니라 종이의 종류로 고른다. 표와 번호는 포스터 고딕, 누르는 것과 이름표는 간판체, 읽는 기사와 사람 이름은 명조, 시간과 날짜와 전화번호는 고정폭이다. 새 쪽지를 만들 때는 먼저 어떤 종이인지 정하고 활자를 따른다.

**글자는 끝까지 검정 규칙.** 종이 위 글자는 `ink` 아니면 `ink-soft`다. 더 옅은 회색을 만들지 않는다. 제목의 자간은 0이고, 줄바꿈은 제목에 `text-wrap: balance`, 문단에 `text-wrap: pretty`를 쓴다.

## Layout

본문은 공통 `.container`(안쪽 폭 1200px, 좌우 여백 24px) 안에 놓이고, 섹션 사이는 `clamp(72px, 9vw, 120px)`, 섹션 제목과 내용 사이는 40px이다. 쪽지 안쪽 여백은 좌우 24–30px이고, 위쪽은 압정이 앉을 자리를 두어 40–56px이다.

격자는 일부러 고르지 않다. 세 장짜리 묶음(진료 과목, 의료진)은 첫 장이 넓고(`1.3fr 1fr 1fr`, `1.35fr 1fr 1fr`), 나머지는 음수 여백으로 앞 장에 22–40px 겹치며 세로로 14–104px 어긋난다. 겹침 순서는 `z-index` 1–3으로 정한다. 쪽지는 저마다 기운다. 쉬고 있는 쪽지의 기울기는 ±0.6도에서 ±3도 사이이고, 섹션 제목 띠는 홀짝으로 -1.4도와 1.1도를 번갈아 쓴다. 압정 위치는 `--pin-x`로 쪽지마다 다르게 준다.

첫 화면은 두 칸이다. 왼쪽에 예약권, 오른쪽에 폭 316px의 영수증 띠가 두 줄 높이로 서고, 예약권 아래 줄에 전화 꼬리표와 고정 공지 오림이 놓인다. 도장은 예약권과 영수증 사이에 걸쳐 붙는다.

**좁아질 때.** 쪽지는 줄어들지 않고 한 줄로 다시 꽂힌다.
- 1100px 이하: 영수증 290px, 예약권 꼬리표 180px, 세 장 묶음은 두 칸으로 바뀌고 한 장이 아래로 내려간다.
- 900px 이하: 첫 화면이 한 칸이 된다. 예약권의 꼬리표가 아래로 내려가 세로 절취선이 가로 절취선으로 바뀌고 반원 홈이 사라진다. 영수증의 줄은 두 단으로 나뉜다. 번호표는 2×2, 명함은 한 줄. 예약권 들기 장면은 꺼진다.
- 640px 이하: 본문 16px, 버튼은 폭 전체, 카드와 번호표가 한 줄.

**좁은 화면의 고정 바.** 900px 이하에서는 공통 하단 고정 바(전화, 예약)가 보인다. 예약권의 자기 버튼이 화면에 60% 이상 보이는 동안에는 `body.is-cta-inview`가 붙어 고정 바가 아래로 내려가 숨는다. 같은 일을 하는 버튼이 한 화면에 두 벌 보이지 않게 하는 장치다.

## Elevation & Depth

깊이는 종이가 판에서 살짝 떠 있는 그림자로만 낸다. 종이 위에 종이를 또 쌓는 계층은 없다. 판 하나, 그 위의 쪽지 한 겹, 쪽지 위의 압정이 전부다.

### Shadow Vocabulary
- **종이 그림자** (`--paper-shadow`: `0 1px 0 rgba(0,0,0,.2), 0 16px 22px -10px rgba(0,0,0,.5)`): 네모난 쪽지 전부, 섹션 제목 띠, 이름표, 도장 딱지.
- **오린 종이 그림자** (`filter: drop-shadow(0 1px 0 rgba(0,0,0,.2)) drop-shadow(0 14px 12px rgba(0,0,0,.34))`): `mask`나 `clip-path`로 모양을 오린 쪽지(예약권, 영수증, 신문 오림, 번호표). `box-shadow`는 모양과 함께 잘리므로, 그림자와 기울기는 바깥 틀 `.lift`가 맡는다.
- **작은 딱지 그림자** (`0 1px 0 rgba(0,0,0,.2), 0 8px 10px -6px rgba(0,0,0,.5)`): 메뉴 탭, 머리의 링크와 예약 탭, 「자세히 보기」 딱지.
- **압정 그림자** (`1px 3px 3px rgba(0,0,0,.45)`): 압정 머리.
- **머리 줄 그림자** (`0 8px 14px -8px rgba(0,0,0,.5)`): 스크롤이 내려간 뒤의 머리 줄.

### Named Rules
**바깥 틀 규칙.** 모양을 오린 쪽지에는 `box-shadow`를 직접 주지 않는다. `.lift`로 감싸서 `drop-shadow`와 `transform`을 바깥에 건다.

**두 단계 규칙.** 모든 전환은 `steps(2, end)`이고 길이는 0.12초(버튼, 탭, 링크) 아니면 0.18초(쪽지, 도장)다. 부드러운 감속 곡선을 쓰지 않는다. `prefers-reduced-motion: reduce`에서는 전환을 모두 끈다.

**집어 드는 장면은 하나 규칙.** 여러 쪽지가 함께 움직이는 장면은 첫 화면 예약권 하나다(포인터가 있는 기기, 901px 이상). 예약권에 포인터나 포커스가 닿으면 예약권은 0도로 서며 8px 올라가고(`scale(1.012)`), 영수증·도장·전화 꼬리표·공지 오림이 각자 한 칸씩 비켜난다. 다른 쪽지에 같은 연쇄 반응을 더하지 않는다.

## Shapes

모서리는 직각이다. 쪽지, 버튼, 탭, 배지, 메뉴 버튼 모두 `border-radius: 0`이고, 홈 화면에서는 공통 부품의 둥근 모서리도 0으로 덮어쓴다. 원은 세 곳에만 있다. 지름 14px의 압정, 지름 132px의 도장(1100px 이하 112px, 900px 이하 104px), 예약권 절취선 위아래의 반지름 14px 반원 홈. 포커스 테두리의 2px는 형태 규칙이 아니라 테두리 마무리다.

종이의 가장자리가 형태를 만든다.
- **절취선:** 3px 굵은 점선(`3px dashed`). 예약권의 본문과 꼬리표 사이, 번호표의 칸 사이.
- **톱니:** `conic-gradient` 마스크로 아래쪽을 뜯어 낸 자리. 영수증은 14px, 신문 오림은 18px 간격.
- **꼬리표 머리:** 왼쪽을 화살 모양으로 깎은 `clip-path`와, 압정 대신 뚫린 끈 구멍(판의 초록이 비친다).
- **오림의 윗단:** 신문과 공지 오림은 위쪽에 8–10px 검은 띠를 두른다.
- **쪽지 안의 줄:** 굵은 구분은 2px 실선, 가는 구분은 1px 점선, 영수증의 구분은 2px 점선.

**도장 딱지.** 「일요일 휴진」은 펠트에 직접 찍은 잉크가 아니라 불투명한 종이 딱지다. 신문지색 바탕에 5px 빨간 테두리와 안쪽 2px 빨간 선(`outline-offset: -11px`)을 두르고, 종이 그림자를 받으며 -13도로 붙는다. 판과 분홍 예약권에 걸쳐 놓이므로, 어느 바탕 위에서도 빨강이 읽히도록 종이를 깔았다. 도장은 쪽지의 기울기 범위(±3도) 밖에 있는 유일한 것이다.

## Components

### Buttons
손으로 누르는 간판 조각이다. 크고 각지고, 눌리면 종이처럼 덜컥 움직인다.
- **Shape:** 직각, 3px 잉크 테두리, 최소 높이 56px, 좌우 26px. 640px 이하에서는 폭 전체.
- **Ink(주 버튼):** 잉크 바탕에 분홍 글자, Do Hyeon 1.375rem. 포인터가 닿으면 `translate(-2px, -3px) rotate(-1.5deg)`로 들린다.
- **Line(보조 버튼):** 바탕 없이 테두리만. 포인터가 닿으면 잉크 바탕에 분홍 글자로 뒤집힌다. 전화번호를 담을 때는 고정폭 700 1.125rem, 말을 담을 때는 Do Hyeon 1.375rem.
- **Active:** 둘 다 `translate(0, 1px)`.
- **Focus:** 종이 위에서는 3px 잉크 테두리, 판 위에서는 3px 분필 테두리. 간격 3px.
- **아이콘:** `icons.svg` 스프라이트의 선 아이콘(22px, 선 굵기 2.4).

### Links
- **글 링크:** Do Hyeon 1.1875rem, 2px 밑줄(간격 5px), 끝에 18px 화살표. 포인터가 닿으면 밑줄이나 글자가 빨강이 된다.
- **딱지 링크:** 섹션 제목 옆의 「자세히 보기」. 마닐라 바탕, 밑줄 없음, 1.6도 기울어 있다가 포인터가 닿으면 0도로 서며 3px 올라간다.

### Chips
- **배지:** 직각, 잉크 바탕에 신문지색 글자, 고정폭 700. 이벤트는 빨강 바탕에 흰 글자, 경고는 바탕 없이 2px 빨간 안쪽 테두리와 빨간 글자.

### Cards / Containers
모든 쪽지는 `.scrap`에서 시작한다. 신문지색 바탕, 잉크 글자, 종이 그림자, 위쪽 10px 지점의 빨간 압정(`--pin-x`로 가로 위치를 정한다).
- **Corner Style:** 직각.
- **Background:** 세 종이 중 하나.
- **Shadow Strategy:** 네모난 쪽지는 종이 그림자, 오린 쪽지는 `.lift`의 `drop-shadow`.
- **Border:** 테두리로 감싸지 않는다. 선은 쪽지 안의 구분과 윗단 띠에만 쓴다.
- **Internal Padding:** 좌우 24–30px, 위 40–56px.
- **색인 카드(진료 과목):** 포스터 고딕 제목, 설명, 2px 실선 아래 1px 점선 목록, 글 링크. 세 장이 마닐라·신문지색·분홍으로 겹친다.
- **명함(의료진):** 명조 이름과 고정폭 직함, 간판체 분야, 옅은 잉크의 경력, 따옴표를 붙인 명조 한마디.
- **신문 오림(원칙):** 10px 검은 윗단, 명조 머리기사, 세 단 본문(단 사이 1px 잉크 선), 아래 톱니. 본문 안 강조는 Pretendard 800. 옆에 분홍 메모가 -4도로 겹쳐 붙는다.
- **번호표(예약 방법):** 마닐라 띠 한 장을 3px 절취선으로 네 칸으로 나누고, 칸마다 CSS 카운터로 01–04를 찍는다.
- **꼬리표(오시는 길):** 마닐라 바탕의 이름·값 목록. 이름은 간판체, 값은 굵기 600, 줄 사이는 1px 점선.
- **공지 오림:** 8px 검은 윗단, 명조 제목과 고정폭 날짜, 줄 사이 1px 점선. 불러오는 동안의 자리 표시는 잉크 12% 띠.

### Navigation
- **머리 줄:** 펠트 바탕, 아래 2px 분필 선(0.28). 뒤 흐림 효과 없음.
- **이름표:** 신문지색 딱지에 Do Hyeon 24px 병원 이름과 고정폭 11px 영문 이름. -1.2도.
- **메뉴 탭:** 마닐라 딱지, Do Hyeon 19px. 홀수는 -1.5도, 짝수는 1.2도로 기울고, 포인터가 닿으면 0도로 서며 3px 올라간다.
- **예약 탭:** 분홍 딱지에 잉크 글자.
- **좁은 화면 메뉴:** 신문지색 면, 위 2px 점선, 항목 사이 1px 점선, Do Hyeon 21px.
- **하단 고정 바(900px 이하):** 깊은 펠트 바탕. 전화는 마닐라, 예약은 분홍, 둘 다 직각에 Do Hyeon 20px. 숨는 조건은 Layout 참고.
- **바닥글:** 깊은 펠트 바탕, 위 2px 분필 선. 이름표의 딱지 처리는 벗긴다.

### 예약권 (Signature)
이 화면에서 가장 큰 쪽지이고 첫 화면과 마지막에 한 번씩 나온다. 분홍 종이를 본문과 꼬리표로 나누고, 그 사이에 3px 세로 절취선과 위아래 반원 홈을 둔다. 꼬리표 폭은 `--stub`(214px, 마지막 예약권은 300px)로 정한다. 본문에는 포스터 고딕 제목, 설명, 버튼 두 개가 들어가고, 꼬리표에는 고정폭 이름과 간판체 값의 짝(첫 화면) 또는 버튼 두 개(마지막)가 들어간다. 첫 화면의 예약권만 집어 드는 장면을 가진다.

### 영수증 띠 (Signature)
「오늘 진료 시간」. 신문지색 종이에 고정폭 활자로 찍고, 아래는 톱니로 끝난다. `board.js`가 진료 시간 설정과 서울 기준 현재 시각으로 30분 줄을 찍는다. 스크립트가 없으면 요일별 진료 시간 세 줄이 그대로 보인다.
- **지난 줄:** 빗금 바탕, 옅은 잉크, 시간에 취소선, 상태 「지남」. 휴진일에는 모든 줄이 「휴진」.
- **점심 줄:** 한 줄로 묶고 빗금 바탕, 옅은 잉크.
- **지금 줄:** 잉크 바탕에 신문지색 글자, 굵게.
- **남은 줄:** 꾸밈 없이 「진료」.
- **합계 줄:** 2px 점선 아래 굵은 한 문장(진료 중·점심·마감·휴진과 다음 진료 시각). 1분마다 다시 찍는다.
- **범위:** 띠는 진료 시간과 현재 시각의 관계만 보여 준다. 빈 예약 시간은 로그인해야 조회되므로 여기서 보여 주지 않고, 「빈 시간은 예약 화면에서 확인합니다.」라는 안내와 예약 화면 링크로 넘긴다.

## Do's and Don'ts

### Do:
- **Do** 새 정보는 새 쪽지로 붙인다. 먼저 어떤 종이(표, 꼬리표, 오림, 영수증, 명함)인지 정하고 바탕색과 활자를 거기서 따른다.
- **Do** 쪽지마다 압정 위치(`--pin-x`)와 기울기를 다르게 준다. 쉬고 있는 쪽지는 ±3도 안에서 기운다.
- **Do** 물러나야 하는 정보는 빗금 바탕과 `ink-soft`로 낮춘다.
- **Do** 모양을 오린 쪽지는 `.lift`로 감싸 그림자와 기울기를 바깥에 건다.
- **Do** 전환은 `steps(2, end)`에 0.12초 또는 0.18초로 쓰고, `prefers-reduced-motion`에서 끈다.
- **Do** 종이 위 포커스는 3px 잉크, 판 위 포커스는 3px 분필 테두리로 보인다.
- **Do** 버튼의 높이는 56px, 하단 고정 바의 버튼은 48px로 둔다.
- **Do** 좁은 화면에서는 쪽지를 줄이지 말고 한 줄로 다시 꽂는다. 세로 절취선은 가로 절취선으로 바꾼다.
- **Do** 영수증의 시간 줄, 전화번호, 번호표 숫자에는 `tabular-nums`를 쓴다.

### Don't:
- **Don't** 사진이나 일러스트를 넣지 않는다. 화면은 글자, 색, 실제 정보로 채운다.
- **Don't** 네 번째 종이 색이나 회색 단계를 만들지 않는다.
- **Don't** 쪽지, 버튼, 탭, 배지의 모서리를 둥글리지 않는다. 원은 압정, 도장, 절취 홈뿐이다.
- **Don't** 부드러운 감속 곡선으로 전환하지 않는다.
- **Don't** 예약권 말고 다른 쪽지에 주변이 함께 움직이는 장면을 더하지 않는다.
- **Don't** 빨강을 종이 바탕이나 버튼 바탕으로 쓰지 않는다.
- **Don't** 영수증 띠에 예약 가능 여부나 남은 자리를 표시하지 않는다. 띠는 진료 시간과 현재 시각만 안다.
- **Don't** 예약권의 버튼이 보이는 동안 하단 고정 바를 함께 띄우지 않는다.
- **Don't** 같은 크기의 같은 카드를 고른 격자로 줄 세우지 않는다. 묶음은 크기와 종이와 높이가 어긋나야 한다.
- **Don't** 이전 모습의 청록·주황 토큰(`--c-primary`, `--c-accent`)과 둥근 모서리(8–28px, 알약형 배지)를 이 세계의 쪽지에 섞지 않는다.
