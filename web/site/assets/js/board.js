/* 홈 「오늘 진료 시간」 영수증 띠
   진료 시간 설정(data-*)과 병원 기준 현재 시각으로 30분 줄을 찍는다.
   실제 예약 현황은 로그인해야 조회되므로 여기서는 시간이 지났는지만 표시한다.
   이 스크립트가 없어도 띠에는 요일별 진료 시간이 그대로 보인다. */
(function () {
  'use strict';

  var slip = document.querySelector('[data-receipt]');
  if (!slip) return;

  function q(sel) { return slip.querySelector(sel); }
  function toMin(hhmm) { var p = hhmm.split(':'); return +p[0] * 60 + +p[1]; }
  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function hhmm(min) { return pad(Math.floor(min / 60)) + ':' + pad(min % 60); }
  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  // 병원 기준 시각(서울). 방문자의 기기 시간대와 무관하게 맞춘다.
  function seoulNow() {
    var parts = {};
    new Intl.DateTimeFormat('en-US', {
      timeZone: 'Asia/Seoul', weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23'
    }).formatToParts(new Date()).forEach(function (p) { parts[p.type] = p.value; });
    var days = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
    return { day: days[parts.weekday], min: +parts.hour * 60 + +parts.minute };
  }

  var d = slip.dataset;
  var open = toMin(d.open), close = toMin(d.close), ls = toMin(d.lunchStart), le = toMin(d.lunchEnd);
  var step = +d.slot || 30;
  var closedDays = (d.closedDays || '').split(',').filter(Boolean).map(Number);
  if (!(close > open) || !(step > 0)) return;

  var rows = q('[data-receipt-rows]');
  var dateEl = q('[data-receipt-date]');
  var sumEl = q('[data-receipt-sum]');

  function row(cls, time, state) {
    var li = el('li', cls);
    li.appendChild(el('span', null, time));
    li.appendChild(el('span', null, state));
    return li;
  }

  function render() {
    var now = seoulNow();
    var isClosedDay = closedDays.indexOf(now.day) >= 0;
    var frag = document.createDocumentFragment();
    var lunchDone = false;

    for (var t = open; t < close; t += step) {
      if (t >= ls && t < le) {
        // 점심은 한 줄로 묶는다
        if (!lunchDone) {
          var inLunch = !isClosedDay && now.min >= ls && now.min < le;
          frag.appendChild(row(inLunch ? 'is-now' : 'is-lunch', d.lunchStart + '–' + d.lunchEnd, inLunch ? '지금 점심' : '점심'));
          lunchDone = true;
        }
        continue;
      }
      if (isClosedDay) { frag.appendChild(row('is-past', hhmm(t), '휴진')); continue; }
      if (now.min >= t + step) frag.appendChild(row('is-past', hhmm(t), '지남'));
      else if (now.min >= t) frag.appendChild(row('is-now', hhmm(t), '지금'));
      else frag.appendChild(row('is-open', hhmm(t), '진료'));
    }
    rows.innerHTML = '';
    rows.appendChild(frag);

    dateEl.textContent = new Intl.DateTimeFormat('ko-KR', { timeZone: 'Asia/Seoul', month: 'long', day: 'numeric', weekday: 'long' }).format(new Date());

    // 닫힌 뒤에는 다음에 문 여는 날을 알려 준다 (휴진 요일은 건너뛴다)
    function nextOpen() {
      var names = ['일', '월', '화', '수', '목', '금', '토'];
      for (var k = 1; k <= 7; k++) {
        var day = (now.day + k) % 7;
        if (closedDays.indexOf(day) < 0) return (k === 1 ? '내일' : names[day] + '요일') + ' ' + d.open;
      }
      return '';
    }
    var sum;
    if (isClosedDay) sum = '오늘은 휴진입니다. 다음 진료 ' + nextOpen();
    else if (now.min < open) sum = '진료 전입니다. ' + d.open + ' 시작';
    else if (now.min >= close) sum = '오늘 진료를 마쳤습니다. 다음 진료 ' + nextOpen();
    else if (now.min >= ls && now.min < le) sum = '점심시간입니다. ' + d.lunchEnd + ' 진료 재개';
    else sum = '진료 중입니다. ' + d.close + ' 마감';
    sumEl.textContent = sum;
  }

  render();
  setInterval(render, 60000);

  /* 좁은 화면의 아래 고정 바는 예약권의 버튼과 같은 일을 한다.
     예약권 버튼이 화면에 보이는 동안에는 고정 바를 내려 둔다. */
  var ownCtas = document.querySelectorAll('.ticket__actions, .ticket__stub--actions');
  if (ownCtas.length && 'IntersectionObserver' in window) {
    var shown = [];
    var watch = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        var i = shown.indexOf(e.target);
        if (e.isIntersecting && i < 0) shown.push(e.target);
        if (!e.isIntersecting && i >= 0) shown.splice(i, 1);
      });
      document.body.classList.toggle('is-cta-inview', shown.length > 0);
    }, { threshold: 0.6 });
    Array.prototype.forEach.call(ownCtas, function (n) { watch.observe(n); });
  }
})();
