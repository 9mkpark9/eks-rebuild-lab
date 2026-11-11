import { useEffect, useLayoutEffect, useState, useSyncExternalStore, type ReactNode } from 'react';
import clinic from '../../clinic.config.json';
import { nodeStore } from './api';
import { useAuth } from './auth';
import { EmrShell } from './emr/EmrShell';
import { ROLE_HOME, roleLabel, roleName } from './lib/roles';
import { shortNode } from './lib/text';
import DirectorSchedule from './pages/director/DirectorSchedule';
import DirectorSlots from './pages/director/DirectorSlots';
import DirectorStats from './pages/director/DirectorStats';
import Login from './pages/Login';
import MyReservations from './pages/MyReservations';
import NurseNotices from './pages/nurse/NurseNotices';
import NurseReservations from './pages/nurse/NurseReservations';
import OwnerHome from './pages/OwnerHome';
import Pets from './pages/Pets';
import Reserve from './pages/Reserve';
import { Link, navigate, useLocation } from './router';
import type { Role } from './types';
import { EmptyState, Icon, PageLoading } from './ui';

interface RouteDef { path: string; title: string; role: Role | null; element: () => ReactNode }
const ROUTES: RouteDef[] = [
  { path: '/app/login', title: '로그인', role: null, element: () => <Login /> },
  // 보호자
  { path: '/app', title: '예약 홈', role: 'OWNER', element: () => <OwnerHome /> },
  { path: '/app/reserve', title: '온라인 예약', role: 'OWNER', element: () => <Reserve /> },
  { path: '/app/reservations', title: '내 예약', role: 'OWNER', element: () => <MyReservations /> },
  { path: '/app/pets', title: '내 반려동물', role: 'OWNER', element: () => <Pets /> },
  // 간호사 전용 — 접수 데스크 업무
  { path: '/app/nurse', title: '예약 현황', role: 'NURSE', element: () => <NurseReservations /> },
  { path: '/app/nurse/notices', title: '공지 관리', role: 'NURSE', element: () => <NurseNotices /> },
  // 원장 전용 — 진료 업무
  { path: '/app/director', title: '내 진료 일정', role: 'DIRECTOR', element: () => <DirectorSchedule /> },
  { path: '/app/director/slots', title: '진료 시간 관리', role: 'DIRECTOR', element: () => <DirectorSlots /> },
  { path: '/app/director/stats', title: '병원 현황', role: 'DIRECTOR', element: () => <DirectorStats /> },
];

const TABS: Record<Role, { to: string; label: string; icon: string }[]> = {
  OWNER: [
    { to: '/app/', label: '홈', icon: 'home' },
    { to: '/app/reserve', label: '예약하기', icon: 'calendar-check' },
    { to: '/app/reservations', label: '내 예약', icon: 'list' },
    { to: '/app/pets', label: '내 반려동물', icon: 'paw' },
  ],
  NURSE: [
    { to: '/app/nurse', label: '예약 현황', icon: 'list' },
    { to: '/app/nurse/notices', label: '공지 관리', icon: 'megaphone' },
  ],
  DIRECTOR: [
    { to: '/app/director', label: '내 진료 일정', icon: 'calendar' },
    { to: '/app/director/slots', label: '진료 시간 관리', icon: 'grid' },
    { to: '/app/director/stats', label: '병원 현황', icon: 'clipboard' },
  ],
};

export default function App() {
  const { user, loading } = useAuth();
  const { path, query } = useLocation();
  const route = ROUTES.find((r) => r.path === path);
  const legacyAdmin = path.startsWith('/app/admin'); // 예전 관리자 주소

  // 접근 제어: 로그인이 필요하면 로그인 화면으로. 역할이 다르면 들여보내지 않고 안내만 한다(간호사 ↔ 원장 전용).
  const redirect = (() => {
    if (loading) return null;
    if (legacyAdmin) return user ? ROLE_HOME[user.role] : '/app/login';
    if (!route || !route.role || user) return null;
    return `/app/login?next=${encodeURIComponent(window.location.pathname + window.location.search)}`;
  })();
  useEffect(() => { if (redirect) navigate(redirect, { replace: true }); }, [redirect]);
  useEffect(() => { document.title = `${route?.title ?? '페이지 없음'} | ${clinic.name}`; }, [route]);

  const forbidden = !!user && !!route?.role && route.role !== user.role;
  const staff = user?.role === 'NURSE' || user?.role === 'DIRECTOR';
  const tabs = user ? TABS[user.role] : [];
  const showTabs = !!user && !!route && route.role === user.role;
  const tabsQuery = staff && query.get('date') ? `?date=${query.get('date')}` : '';

  // 간호사·원장은 홈페이지 틀 대신 EMR 화면 틀(ChartNote 디자인)로 일한다
  const emr = staff && !loading && !redirect && path !== '/app/login';
  // 보호자 화면은 소개 페이지와 같은 「병원 게시판」 세계(body.board)를 쓰고, EMR 화면에서는 뗀다
  useLayoutEffect(() => { document.body.classList.toggle('board', !emr); }, [emr]);
  if (emr) {
    return (
      <EmrShell tabs={tabs}>
        {forbidden ? (
          <section className="emr-panel">
            <h2 className="emr-title">접근 제한</h2>
            <div className="emr-empty">
              <p style={{ fontWeight: 700, color: 'var(--emr-text)', fontSize: 16 }}><Icon name="lock" className="icon--sm" /> {roleName(route!.role!)} 전용 화면입니다.</p>
              <p style={{ margin: '6px 0 12px' }}>{user!.name} {roleLabel(user!.role, user!.vetId)} 계정으로는 이 화면을 볼 수 없습니다.</p>
              <Link to={ROLE_HOME[user!.role]} className="emr-btn emr-btn-primary">내 화면으로</Link>
            </div>
          </section>
        ) : route ? route.element() : (
          <section className="emr-panel"><h2 className="emr-title">화면 없음</h2><div className="emr-empty">주소가 바뀌었거나 없는 화면입니다.</div></section>
        )}
      </EmrShell>
    );
  }

  return (
    <div className="app">
      <AppHeader />
      {showTabs && (
        <nav className={`app-tabs${staff ? ` app-tabs--staff app-tabs--${user!.role.toLowerCase()}` : ''}`} aria-label="메뉴">
          <div className="container app-tabs__inner">
            {staff && <span className="app-tabs__badge"><Icon name="lock" />{roleName(user!.role)} 전용</span>}
            {tabs.map((t) => (
              <Link key={t.to} to={t.to + tabsQuery} className="app-tabs__tab" aria-current={path === t.to.replace(/\/$/, '') ? 'page' : undefined}>
                <Icon name={t.icon} />{t.label}
              </Link>
            ))}
          </div>
        </nav>
      )}
      <main id="main" className={`app-main${path === '/app/login' ? ' app-main--login' : ''}`}>
        <div className="container">
          {loading || redirect ? <PageLoading /> : forbidden ? (
            <EmptyState icon="lock" title={`${roleName(route!.role!)} 전용 화면입니다`}
              desc={`${user!.name} ${roleLabel(user!.role, user!.vetId)}님 계정으로는 이 화면을 볼 수 없어요.`}
              action={<Link to={ROLE_HOME[user!.role]} className="btn btn--primary btn--sm">내 화면으로</Link>} />
          ) : route ? route.element() : (
            <EmptyState icon="search" title="페이지를 찾을 수 없어요" desc="주소가 바뀌었거나 없는 화면입니다."
              action={<Link to="/app/" className="btn btn--primary btn--sm">예약 홈으로</Link>} />
          )}
        </div>
      </main>
      <AppFooter />
    </div>
  );
}

function AppHeader() {
  const { user, logout } = useAuth();
  const [open, setOpen] = useState(false);
  async function onLogout() {
    setOpen(false);
    await logout();
    navigate('/app/login', { replace: true });
  }
  return (
    <header className="header is-scrolled">
      <div className="container header__inner">
        <a className="brand" href="/" aria-label={`${clinic.name} 홈`}>
          <img className="brand__mark" src="/assets/img/favicon.svg" alt="" width="40" height="40" />
          <span className="brand__text"><span className="brand__name">{clinic.name}</span><span className="brand__en">{clinic.nameEn}</span></span>
        </a>
        <nav className="gnb" aria-label="병원 안내">
          <ul>
            <li><a href="/about">병원 소개</a></li>
            <li><a href="/doctors">의료진</a></li>
            <li><a href="/services">진료 안내</a></li>
            <li><a href="/notices">공지사항</a></li>
          </ul>
        </nav>
        <div className="header__actions">
          {user ? (
            <div className="user-menu">
              <button className="user-menu__btn" type="button" aria-expanded={open} aria-label={`${user.name} 계정 메뉴`} onClick={() => setOpen((v) => !v)}>
                <span className={`user-menu__avatar user-menu__avatar--${user.role.toLowerCase()}`}><Icon name={user.role === 'DIRECTOR' ? 'stethoscope' : user.role === 'NURSE' ? 'clipboard' : 'user'} /></span>
                <span className="user-menu__name">{user.name}<small>{roleLabel(user.role, user.vetId)}</small></span>
                <Icon name="chevron-down" className="icon--sm" />
              </button>
              {open && (
                <div className="user-menu__panel">
                  <p className="user-menu__id">{user.loginId}</p>
                  <a href="/">소개 페이지로</a>
                  <button type="button" onClick={onLogout}><Icon name="logout" />로그아웃</button>
                </div>
              )}
            </div>
          ) : (
            <Link to="/app/login" className="btn btn--primary btn--sm">로그인</Link>
          )}
        </div>
      </div>
    </header>
  );
}

function AppFooter() {
  const node = useSyncExternalStore(nodeStore.subscribe, nodeStore.get);
  return (
    <footer className="app-footer">
      <div className="container app-footer__inner">
        <p><strong>{clinic.name}</strong> · {clinic.address} · <a href={`tel:${clinic.phone.replace(/[^0-9]/g, '')}`}>{clinic.phone}</a></p>
        <p className="app-footer__node" title="분산 확인용 응답 헤더 X-Web-Node / X-Served-By">
          <Icon name="server" className="icon--sm" />마지막 응답 · WEB <code>{shortNode(node.web)}</code> · WAS <code>{shortNode(node.was)}</code>
        </p>
      </div>
    </footer>
  );
}
