import { useEffect, useState, useSyncExternalStore, type ReactNode } from 'react';
import clinic from '../../../clinic.config.json';
import { nodeStore } from '../api';
import { useAuth } from '../auth';
import { roleLabel } from '../lib/roles';
import { shortNode } from '../lib/text';
import { Link, navigate, useLocation } from '../router';
import { Icon } from '../ui';
import './emr.css';

export interface EmrTab { to: string; label: string; icon: string }

const WEEK = ['일', '월', '화', '수', '목', '금', '토'];
const pad = (n: number) => String(n).padStart(2, '0');

function useClock() {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => { const t = window.setInterval(() => setNow(new Date()), 1000); return () => window.clearInterval(t); }, []);
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} (${WEEK[now.getDay()]}) ${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
}

/** 간호사·원장 화면 틀: 상단 메뉴 막대 → 폴더 탭 → 본문 → 하단 상태 막대 (ChartNote EMR 배치) */
export function EmrShell({ tabs, children }: { tabs: EmrTab[]; children: ReactNode }) {
  const { user, logout } = useAuth();
  const { path, query } = useLocation();
  const node = useSyncExternalStore(nodeStore.subscribe, nodeStore.get);
  const clock = useClock();
  const dateQuery = query.get('date') ? `?date=${query.get('date')}` : '';
  const desk = user?.role === 'DIRECTOR' ? '원장 진료실' : '간호사 접수 데스크';

  async function onLogout() {
    await logout();
    navigate('/app/login', { replace: true });
  }

  return (
    <div className="emr-shell">
      <nav className="emr-menu" aria-label="EMR 메뉴">
        <span className="emr-menu__brand">{clinic.name} EMR <small>v1.0</small></span>
        <span className="emr-menu__role">{desk}</span>
        {tabs.map((t) => (
          <Link key={t.to} to={t.to + dateQuery} className="emr-menu-item emr-menu__nav" aria-current={path === t.to ? 'page' : undefined}>
            <Icon name={t.icon} />{t.label}
          </Link>
        ))}
        <span className="emr-menu__right">
          <a className="emr-menu-item emr-menu__home" href="/" target="_blank" rel="noopener"><Icon name="home" />홈페이지</a>
          {user && <span className="emr-menu__user"><strong>{user.name}</strong>{roleLabel(user.role, user.vetId)}</span>}
          <button className="emr-menu-item" type="button" onClick={onLogout}><Icon name="logout" />로그아웃</button>
        </span>
      </nav>
      <div className="emr-tabs" role="tablist" aria-label="화면">
        {tabs.map((t) => (
          <Link key={t.to} to={t.to + dateQuery} className="emr-tab" role="tab" data-active={path === t.to} aria-selected={path === t.to}>
            <Icon name={t.icon} />{t.label}
          </Link>
        ))}
      </div>
      <main id="main" className="emr-content">{children}</main>
      <footer className="emr-statusbar">
        <span>접속 <b>{user?.name}</b> ({user ? roleLabel(user.role, user.vetId) : '-'})</span>
        <span className="hide-sm">WEB <code>{shortNode(node.web)}</code>{node.webVersion && <> {node.webVersion}</>} · WAS <code>{shortNode(node.was)}</code>{node.wasVersion && <> {node.wasVersion}</>}</span>
        <span className="ok">● 서버 정상</span>
        <span style={{ marginLeft: 'auto' }}>{clock}</span>
        <span className="hide-sm">{clinic.name} {clinic.phone}</span>
      </footer>
    </div>
  );
}
