/* 소개 페이지 공통 스크립트
   - 헤더·모바일 메뉴·빠른 메뉴, 지금 진료 중 표시, 오늘 진료 시간 강조
   - 공지사항: GET /api/notices, /api/notices/{id} (WEB → 내부 ALB → WAS)
   소개 페이지는 정적 HTML이라 이 스크립트가 없어도 내용은 모두 보인다. */
(function () {
  'use strict';

  var CATEGORY = {
    NOTICE: { label: '공지', cls: 'badge--primary' },
    EVENT: { label: '이벤트', cls: 'badge--accent' },
    CLOSED: { label: '휴진', cls: 'badge--danger' }
  };

  function $(sel, root) { return (root || document).querySelector(sel); }
  function $$(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }
  function toMin(hhmm) { var p = hhmm.split(':'); return +p[0] * 60 + +p[1]; }
  function fmtDate(iso) { return iso ? iso.slice(0, 10).replace(/-/g, '.') : ''; }

  // 병원 기준 시각(서울). 방문자의 기기 시간대와 무관하게 진료 상태를 맞춘다.
  function seoulNow() {
    var parts = {};
    new Intl.DateTimeFormat('en-US', {
      timeZone: 'Asia/Seoul', weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23'
    }).formatToParts(new Date()).forEach(function (p) { parts[p.type] = p.value; });
    var days = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
    return { day: days[parts.weekday], min: +parts.hour * 60 + +parts.minute };
  }

  /* ---------- 헤더 ---------- */
  var header = $('[data-header]');
  function onScroll() { if (header) header.classList.toggle('is-scrolled', window.scrollY > 8); }
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  var toggle = $('[data-menu-toggle]');
  var menu = $('#mobile-menu');
  if (toggle && menu) {
    toggle.addEventListener('click', function () {
      var open = toggle.getAttribute('aria-expanded') !== 'true';
      toggle.setAttribute('aria-expanded', String(open));
      menu.hidden = !open;
      toggle.querySelector('use').setAttribute('href', '/assets/img/icons.svg#' + (open ? 'close' : 'menu'));
      toggle.querySelector('.sr-only').textContent = open ? '메뉴 닫기' : '메뉴 열기';
    });
    $$('a', menu).forEach(function (a) {
      a.addEventListener('click', function () { if (toggle.getAttribute('aria-expanded') === 'true') toggle.click(); });
    });
  }

  $$('[data-scroll-top]').forEach(function (b) {
    b.addEventListener('click', function () { window.scrollTo({ top: 0, behavior: 'smooth' }); });
  });

  /* ---------- 진료 상태 · 오늘 강조 ---------- */
  var status = $('[data-clinic-status]');
  var now = seoulNow();
  if (status) {
    var d = status.dataset;
    var closed = (d.closedDays || '').split(',').filter(Boolean).map(Number);
    var open = toMin(d.open), close = toMin(d.close), ls = toMin(d.lunchStart), le = toMin(d.lunchEnd);
    var state, text;
    if (closed.indexOf(now.day) >= 0) { state = 'closed'; text = '오늘은 휴진일 · 온라인 예약은 24시간 가능'; }
    else if (now.min < open) { state = 'closed'; text = '진료 전 · ' + d.open + ' 진료 시작'; }
    else if (now.min >= ls && now.min < le) { state = 'lunch'; text = '점심시간 · ' + d.lunchEnd + ' 진료 재개'; }
    else if (now.min < close) { state = 'open'; text = '지금 진료 중 · ' + d.close + ' 진료 마감'; }
    else { state = 'closed'; text = '오늘 진료 종료 · 온라인 예약은 24시간 가능'; }
    status.dataset.state = state;
    $('[data-clinic-status-text]', status).textContent = text;
  }
  $$('[data-hours-table] tr[data-days]').forEach(function (tr) {
    if (tr.dataset.days.split(',').map(Number).indexOf(now.day) >= 0) tr.classList.add('is-today');
  });

  /* ---------- 스크롤 등장 효과 ---------- */
  var reveals = $$('.reveal');
  // 첫 화면에 이미 들어와 있는 요소는 페이드 없이 바로 보여 준다 (서브 페이지 첫 화면이 비어 보이지 않게)
  var viewH = window.innerHeight || document.documentElement.clientHeight;
  reveals = reveals.filter(function (n) {
    if (n.getBoundingClientRect().top >= viewH) return true;
    n.classList.add('is-instant', 'is-visible');
    return false;
  });
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('is-visible'); io.unobserve(e.target); }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.05 });
    reveals.forEach(function (n) { io.observe(n); });
  } else {
    reveals.forEach(function (n) { n.classList.add('is-visible'); });
  }

  /* ---------- 하위 메뉴 현재 위치 ---------- */
  var subnav = $('[data-subnav]');
  if (subnav && 'IntersectionObserver' in window) {
    var links = $$('a[href^="#"]', subnav);
    var targets = links.map(function (a) { return document.getElementById(a.getAttribute('href').slice(1)); }).filter(Boolean);
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        links.forEach(function (a) {
          var on = a.getAttribute('href') === '#' + e.target.id;
          a.classList.toggle('is-active', on);
          if (on && a.scrollIntoView && subnav.scrollWidth > subnav.clientWidth) a.scrollIntoView({ block: 'nearest', inline: 'center' });
        });
      });
    }, { rootMargin: '-45% 0px -50% 0px' });
    targets.forEach(function (t) { spy.observe(t); });
  }

  /* ---------- 공지사항 API ---------- */
  function getJson(url) {
    return fetch(url, { headers: { Accept: 'application/json' }, credentials: 'same-origin' }).then(function (r) {
      if (!r.ok) { var err = new Error('HTTP ' + r.status); err.status = r.status; throw err; }
      return r.json();
    });
  }
  function sortNotices(list) {
    return list.slice().sort(function (a, b) {
      if (!!b.pinned - !!a.pinned) return !!b.pinned - !!a.pinned;
      return (b.createdAt || '').localeCompare(a.createdAt || '');
    });
  }
  function badge(category) {
    var c = CATEGORY[category] || CATEGORY.NOTICE;
    return el('span', 'badge ' + c.cls, c.label);
  }

  var homeList = $('[data-notice-list]');
  var pinnedStrip = $('[data-pinned-notice]');
  var board = $('[data-board]');

  if (homeList || pinnedStrip || board) {
    var noticeId = board ? new URLSearchParams(location.search).get('id') : null;
    if (noticeId) {
      renderDetail(noticeId);
    } else {
      getJson('/api/notices').then(function (list) {
        list = sortNotices(Array.isArray(list) ? list : []);
        if (homeList) renderHomeList(list);
        if (pinnedStrip) renderPinned(list);
        if (board) renderBoard(list);
      }).catch(function () {
        if (homeList) { homeList.innerHTML = ''; homeList.appendChild(el('li', 'notice-empty', '공지사항을 불러오지 못했습니다. 잠시 후 다시 확인해 주세요.')); }
        if (board) boardState('alert', '공지사항을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.');
      });
    }
  }

  function renderHomeList(list) {
    var limit = +(homeList.dataset.limit || 5);
    homeList.innerHTML = '';
    if (!list.length) { homeList.appendChild(el('li', 'notice-empty', '등록된 공지사항이 없습니다.')); return; }
    list.slice(0, limit).forEach(function (n) {
      var li = el('li');
      var a = el('a');
      a.href = '/notices?id=' + encodeURIComponent(n.noticeId);
      a.appendChild(badge(n.category));
      a.appendChild(el('span', 'notice-list__title', n.title));
      a.appendChild(el('span', 'notice-list__date', fmtDate(n.createdAt).slice(5)));
      li.appendChild(a);
      homeList.appendChild(li);
    });
  }

  function renderPinned(list) {
    var p = list.filter(function (n) { return n.pinned; })[0];
    if (!p) return;
    var c = CATEGORY[p.category] || CATEGORY.NOTICE;
    var cat = $('[data-pinned-category]', pinnedStrip);
    cat.textContent = c.label;
    cat.className = 'badge ' + c.cls;
    $('[data-pinned-title]', pinnedStrip).textContent = p.title;
    $('[data-pinned-date]', pinnedStrip).textContent = fmtDate(p.createdAt);
    $('a', pinnedStrip).href = '/notices?id=' + encodeURIComponent(p.noticeId);
    pinnedStrip.hidden = false;
  }

  function boardState(icon, text) {
    var body = $('[data-board-body]');
    body.innerHTML = '';
    var box = el('div', 'board__state');
    box.innerHTML = '<svg class="icon" aria-hidden="true"><use href="/assets/img/icons.svg#' + icon + '"/></svg>';
    box.appendChild(el('p', null, text));
    body.appendChild(box);
  }

  function renderBoard(all) {
    var body = $('[data-board-body]');
    var count = $('[data-board-count]');
    var chips = $$('[data-filter]');
    function draw(filter) {
      var list = filter ? all.filter(function (n) { return n.category === filter; }) : all;
      count.innerHTML = '';
      count.appendChild(document.createTextNode('총 '));
      count.appendChild(el('strong', null, String(list.length)));
      count.appendChild(document.createTextNode('건'));
      if (!list.length) { boardState('megaphone', '해당 분류의 공지사항이 없습니다.'); return; }
      body.innerHTML = '';
      var num = list.filter(function (n) { return !n.pinned; }).length;
      list.forEach(function (n) {
        var row = el('a', 'board__row board__row--link' + (n.pinned ? ' is-pinned' : ''));
        row.href = '/notices?id=' + encodeURIComponent(n.noticeId);
        var numCell = el('span', 'board__num');
        if (n.pinned) numCell.appendChild(el('span', 'badge badge--navy', '필독'));
        else numCell.textContent = String(num--);
        row.appendChild(numCell);
        row.appendChild(badge(n.category));
        row.appendChild(el('span', 'board__title', n.title));
        row.appendChild(el('span', 'board__date', fmtDate(n.createdAt)));
        body.appendChild(row);
      });
    }
    chips.forEach(function (c) {
      c.addEventListener('click', function () {
        chips.forEach(function (x) { x.setAttribute('aria-pressed', String(x === c)); });
        draw(c.dataset.filter);
      });
    });
    draw('');
  }

  function renderDetail(id) {
    $('[data-board-view="list"]').hidden = true;
    var view = $('[data-board-view="detail"]');
    view.hidden = false;
    getJson('/api/notices/' + encodeURIComponent(id)).then(function (n) {
      var c = CATEGORY[n.category] || CATEGORY.NOTICE;
      var cat = $('[data-article-category]', view);
      cat.textContent = c.label;
      cat.className = 'badge ' + c.cls;
      $('[data-article-title]', view).textContent = n.title;
      $('[data-article-date]', view).textContent = fmtDate(n.createdAt);
      $('[data-article-body]', view).textContent = n.content || '';
      document.title = n.title + ' | ' + document.title.split('|').pop().trim();
    }).catch(function (e) {
      $('[data-article-title]', view).textContent = e.status === 404 ? '삭제되었거나 없는 공지사항입니다.' : '공지사항을 불러오지 못했습니다.';
      $('[data-article-body]', view).textContent = '목록으로 돌아가 다른 공지사항을 확인해 주세요.';
    });
  }
})();
