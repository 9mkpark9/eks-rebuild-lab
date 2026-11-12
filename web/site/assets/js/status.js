/* 상태 쪽지 (pages/status.html)
   네 부분(web, auth, clinic, reservation)에 따로따로 물어보고, 답이 오는 대로 그 줄만 고쳐 적는다.
   한 곳이 늦거나 멈춰도 다른 줄은 기다리지 않는다.
     · web         /health 응답의 헤더 X-Web-Version, X-Web-Node
     · 서비스 3개   /api/status/<이름> 의 JSON { service, status, version, servedBy }
   3초 안에 답이 없거나 2xx 가 아니면 「응답 없음」으로 적는다. */
(function () {
  'use strict';

  var root = document.querySelector('[data-status]');
  if (!root || !window.fetch) return;

  var rows = Array.prototype.slice.call(root.querySelectorAll('[data-service]'));
  var timeEl = root.querySelector('[data-status-time]');
  var sumEl = root.querySelector('[data-status-sum]');
  var INTERVAL = Number(root.getAttribute('data-interval')) || 5000;
  var TIMEOUT = 3000;
  var LABEL = { ok: '정상', down: '응답 없음' };
  var timer = null;
  var running = false;

  function setText(el, text) {
    if (el && el.textContent !== text) el.textContent = text;
  }

  function write(row, state, info) {
    var prev = row.getAttribute('data-state');
    row.setAttribute('data-state', state);
    setText(row.querySelector('[data-cell="state"]'), LABEL[state]);
    setText(row.querySelector('[data-cell="version"]'), info && info.version ? info.version : '—');
    setText(row.querySelector('[data-cell="node"]'), info && info.node ? info.node : '—');
    // 처음 채워질 때는 움직이지 않는다. 정상 ↔ 응답 없음으로 바뀐 줄만 한 번 움직인다.
    if (prev !== state && prev !== 'wait') {
      row.classList.remove('is-changed');
      void row.offsetWidth;
      row.classList.add('is-changed');
    }
  }

  function ask(row) {
    var ctrl = window.AbortController ? new AbortController() : null;
    var giveUp = setTimeout(function () { if (ctrl) ctrl.abort(); }, TIMEOUT);
    return fetch(row.getAttribute('data-url'), {
      cache: 'no-store',
      headers: { Accept: 'application/json' },
      signal: ctrl ? ctrl.signal : undefined
    }).then(function (res) {
      if (!res.ok) throw new Error(String(res.status));
      if (row.getAttribute('data-source') === 'headers') {
        return { version: res.headers.get('X-Web-Version'), node: res.headers.get('X-Web-Node') };
      }
      return res.json().then(function (body) { return { version: body.version, node: body.servedBy }; });
    }).then(function (info) {
      write(row, 'ok', info);
    }, function () {
      write(row, 'down', null);
    }).then(function () {
      clearTimeout(giveUp);
    });
  }

  function pad(n) { return n < 10 ? '0' + n : String(n); }

  function summarize() {
    var down = rows.filter(function (r) { return r.getAttribute('data-state') === 'down'; })
      .map(function (r) { return r.getAttribute('data-service'); });
    var total = rows.length;
    setText(sumEl, down.length === 0
      ? total + '곳 모두 정상'
      : total + '곳 중 ' + (total - down.length) + '곳 정상 · ' + down.join(', ') + ' 응답 없음');
    var now = new Date();
    setText(timeEl, (now.getMonth() + 1) + '월 ' + now.getDate() + '일 ' +
      pad(now.getHours()) + ':' + pad(now.getMinutes()) + ':' + pad(now.getSeconds()) +
      ' 확인 · ' + Math.round(INTERVAL / 1000) + '초마다 다시 확인');
  }

  function round() {
    if (running) return;
    running = true;
    clearTimeout(timer);
    Promise.all(rows.map(ask)).then(function () {
      running = false;
      summarize();
      // 보이지 않는 탭에서는 묻지 않는다. 다시 보이면 바로 한 번 묻는다.
      if (!document.hidden) timer = setTimeout(round, INTERVAL);
    });
  }

  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) round();
  });

  round();
})();
