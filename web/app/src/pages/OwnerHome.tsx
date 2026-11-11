import { useCallback, useEffect, useState } from 'react';
import { api, messageOf } from '../api';
import { useAuth } from '../auth';
import { dateOf, isPast, korDate, korTime, timeOf } from '../lib/date';
import { Link } from '../router';
import type { Notice, Pet, Reservation } from '../types';
import { ErrorBox, Icon, PageLoading, SPECIES_LABEL, SpeciesAvatar, StatusBadge, TypeBadge } from '../ui';

export default function OwnerHome() {
  const { user } = useAuth();
  const [data, setData] = useState<{ pets: Pet[]; resv: Reservation[]; notice: Notice | null } | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    setError(null);
    Promise.all([api.pets(), api.myReservations(), api.notices().catch(() => [] as Notice[])])
      .then(([pets, resv, notices]) => setData({ pets, resv, notice: notices.find((n) => n.pinned) ?? null }))
      .catch((e) => setError(messageOf(e)));
  }, []);
  useEffect(load, [load]);

  if (error) return <ErrorBox message={error} onRetry={load} />;
  if (!data) return <PageLoading />;

  const upcoming = data.resv.filter((r) => r.status !== 'CANCELLED' && !isPast(r.startAt));
  const next = upcoming[0];
  const pending = upcoming.filter((r) => r.status === 'REQUESTED').length;

  return (
    <div className="stack-lg">
      <section className="welcome">
        <div>
          <p className="welcome__hi">안녕하세요,</p>
          <h1 className="welcome__name">{user?.name} 보호자님</h1>
          <p className="welcome__desc">
            {data.pets.length ? `${data.pets.map((p) => p.name).join(', ')}의 건강, 오늘도 함께 챙길게요.` : '반려동물을 등록하고 첫 예약을 시작해 보세요.'}
          </p>
        </div>
        <Link to="/app/reserve" className="btn btn--accent btn--lg"><Icon name="calendar-check" />새 예약하기</Link>
      </section>

      <div className="stats">
        <Link to="/app/reservations" className="stat"><span className="stat__label">다가오는 예약</span><strong className="stat__value">{upcoming.length}<small>건</small></strong></Link>
        <Link to="/app/reservations" className="stat"><span className="stat__label">승인 대기</span><strong className="stat__value stat__value--warn">{pending}<small>건</small></strong></Link>
        <Link to="/app/pets" className="stat"><span className="stat__label">등록한 반려동물</span><strong className="stat__value">{data.pets.length}<small>마리</small></strong></Link>
      </div>

      <div className="home-grid">
        <section className="card">
          <header className="card__head">
            <h2 className="card__title"><Icon name="calendar" />다음 예약</h2>
            <Link to="/app/reservations" className="text-link-sm">전체 보기<Icon name="chevron-right" /></Link>
          </header>
          {next ? (
            <div className="next-visit">
              <div className="next-visit__date">
                <span>{korDate(dateOf(next.startAt))}</span>
                <strong>{korTime(timeOf(next.startAt))}</strong>
              </div>
              <ul className="next-visit__meta">
                <li><SpeciesAvatar species={next.petSpecies} size="sm" /><strong>{next.petName}</strong></li>
                <li><TypeBadge type={next.visitType} /><StatusBadge status={next.status} /></li>
                <li className="muted"><Icon name="doctor" />{next.vetName} {next.vetTitle}</li>
              </ul>
              {next.status === 'REQUESTED' && <p className="notice-box notice-box--warn"><Icon name="clock" />시간은 잡혀 있어요. 병원에서 확인하면 ‘예약 확정’으로 바뀝니다.</p>}
            </div>
          ) : (
            <div className="next-visit next-visit--empty">
              <p>다가오는 예약이 없어요.</p>
              <Link to="/app/reserve" className="btn btn--primary btn--sm">예약하러 가기</Link>
            </div>
          )}
        </section>

        <section className="card">
          <header className="card__head">
            <h2 className="card__title"><Icon name="paw" />내 반려동물</h2>
            <Link to="/app/pets" className="text-link-sm">관리<Icon name="chevron-right" /></Link>
          </header>
          {data.pets.length ? (
            <ul className="mini-pets">
              {data.pets.map((p) => (
                <li key={p.petId}>
                  <SpeciesAvatar species={p.species} />
                  <span><strong>{p.name}</strong><small>{SPECIES_LABEL[p.species]} · {p.age}살</small></span>
                  <Link to={`/app/reserve?pet=${p.petId}`} className="btn btn--xs btn--outline">예약</Link>
                </li>
              ))}
            </ul>
          ) : (
            <div className="next-visit next-visit--empty">
              <p>등록된 반려동물이 없어요.</p>
              <Link to="/app/pets" className="btn btn--primary btn--sm">반려동물 등록</Link>
            </div>
          )}
        </section>
      </div>

      {data.notice && (
        <a className="home-notice" href={`/notices?id=${data.notice.noticeId}`}>
          <span className="home-notice__icon"><Icon name="megaphone" /></span>
          <span className="home-notice__text"><small>병원 소식</small><strong>{data.notice.title}</strong></span>
          <Icon name="chevron-right" />
        </a>
      )}
    </div>
  );
}
