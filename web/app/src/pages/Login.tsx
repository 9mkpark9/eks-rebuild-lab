import { useEffect, useState, type FormEvent } from 'react';
import clinic from '../../../clinic.config.json';
import { api, messageOf } from '../api';
import { useAuth } from '../auth';
import { ROLE_HOME } from '../lib/roles';
import { navigate, useLocation } from '../router';
import { Icon, Spinner } from '../ui';

// 로컬 모의 서버에서만 보이는 체험 버튼. 부록 A의 Locust 테스트 계정과 같다.
const IS_LOCAL = ['localhost', '127.0.0.1', '[::1]'].includes(window.location.hostname);
const DEMO_PASSWORD = 'test-only';

function safeNext(next: string | null) {
  return next && next.startsWith('/app') && !next.startsWith('/app/login') ? next : null;
}

export default function Login() {
  const { user, setUser } = useAuth();
  const { query } = useLocation();
  const next = safeNext(query.get('next'));
  const [loginId, setLoginId] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (user) navigate(next ?? ROLE_HOME[user.role], { replace: true });
  }, [user, next]);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!loginId.trim() || !password) return setError('아이디와 비밀번호를 입력해 주세요.');
    setBusy(true);
    setError(null);
    try {
      setUser(await api.login(loginId.trim(), password));
    } catch (err) {
      setError(messageOf(err));
      setBusy(false);
    }
  }

  return (
    <div className="login">
      <section className="login__visual" aria-hidden="true">
        <p className="login__headline">보호자님,<br />반갑습니다</p>
        <p className="login__sub">로그인하면 진료 예약과 변경, 반려동물 정보를 한곳에서 관리할 수 있어요.</p>
        <dl className="login__facts">
          <div><dt>진료 1건</dt><dd>{clinic.slotMinutes}분</dd></div>
          <div><dt>예약 가능</dt><dd>{clinic.bookingDays}일 앞까지</dd></div>
          <div><dt>진료 시간</dt><dd>{clinic.hours.label}</dd></div>
        </dl>
      </section>
      <section className="login__panel">
        <h1 className="login__title">로그인</h1>
        <p className="login__desc">{clinic.name} 보호자 계정 또는 직원 계정으로 로그인하세요.</p>
        {next?.startsWith('/app/reserve') && (
          <p className="notice-box notice-box--info"><Icon name="info" />온라인 예약은 로그인 후 이용할 수 있어요.</p>
        )}
        <form className="form-stack" onSubmit={submit} noValidate>
          <label className="field">
            <span className="field__label">아이디</span>
            <input className="input" value={loginId} onChange={(e) => setLoginId(e.target.value)} autoComplete="username" autoCapitalize="none" spellCheck={false} placeholder="아이디" />
          </label>
          <label className="field">
            <span className="field__label">비밀번호</span>
            <input className="input" type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" placeholder="비밀번호" />
          </label>
          {error && <p className="form-error" role="alert"><Icon name="alert" />{error}</p>}
          <button className="btn btn--primary btn--lg btn--block" type="submit" disabled={busy}>{busy ? <Spinner label="로그인 중" /> : '로그인'}</button>
        </form>
        <p className="login__help">
          계정이 없으신가요? 첫 방문 때 접수처에서 만들어 드립니다.<br />
          전화 예약 <a href={`tel:${clinic.phone.replace(/[^0-9]/g, '')}`}><strong>{clinic.phone}</strong></a>
        </p>
        {IS_LOCAL && (
          <div className="demo-box">
            <p className="demo-box__title"><Icon name="server" />로컬 모의 서버 테스트 계정</p>
            <p className="demo-box__desc">보호자 owner001~owner300 · 간호사 admin1, admin2 · 원장 vet1~vet3 (비밀번호 공통)</p>
            <div className="demo-box__actions">
              <button className="btn btn--xs btn--outline" type="button" onClick={() => { setLoginId('owner001'); setPassword(DEMO_PASSWORD); }}>보호자로 채우기</button>
              <button className="btn btn--xs btn--outline" type="button" onClick={() => { setLoginId('admin1'); setPassword(DEMO_PASSWORD); }}>간호사로 채우기</button>
              <button className="btn btn--xs btn--outline" type="button" onClick={() => { setLoginId('vet1'); setPassword(DEMO_PASSWORD); }}>원장으로 채우기</button>
            </div>
          </div>
        )}
      </section>
    </div>
  );
}
