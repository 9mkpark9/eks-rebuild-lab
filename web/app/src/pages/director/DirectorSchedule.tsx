import { useCallback, useEffect, useState } from 'react';
import clinic from '../../../../clinic.config.json';
import { api, messageOf } from '../../api';
import { useAuth } from '../../auth';
import { DateListPanel, EmrError, EmrLoading, Panel, Pill, StatusPill, TypeTag } from '../../emr/parts';
import { isPast, korDate, nowIso, timeOf, todayYmd } from '../../lib/date';
import { myVet } from '../../lib/roles';
import { Link } from '../../router';
import type { DirectorSlot } from '../../types';
import { Icon, SPECIES_LABEL, SpeciesAvatar } from '../../ui';
import { useStaffDate } from '../staff/useStaffDate';

const endOf = (hhmm: string) => {
  const [h, m] = hhmm.split(':').map(Number);
  const t = h * 60 + m + clinic.slotMinutes;
  return `${String(Math.floor(t / 60)).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}`;
};

/** 원장 전용: 내가 맡은 하루 진료 목록 (진료실 화면) */
export default function DirectorSchedule() {
  const { user } = useAuth();
  const vet = myVet(user);
  const [date, setDate] = useStaffDate();
  const [slots, setSlots] = useState<DirectorSlot[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<number | null>(null);

  const load = useCallback(() => {
    setError(null);
    api.directorSchedule(date).then((s) => {
      setSlots(s);
      // 기본 선택: 오늘이면 다음 진료, 아니면 첫 예약
      const now = nowIso();
      const first = (date === todayYmd() ? s.find((x) => x.reservation && x.startAt > now) : undefined) ?? s.find((x) => x.reservation);
      setSelectedId((cur) => (cur && s.some((x) => x.slotId === cur) ? cur : first?.slotId ?? null));
    }).catch((e) => setError(messageOf(e)));
  }, [date]);
  useEffect(() => { setSlots(null); setSelectedId(null); load(); }, [load]);

  const isToday = date === todayYmd();
  const now = nowIso();
  const list = slots ?? [];
  const booked = list.filter((s) => s.reservation);
  const current = (s: DirectorSlot) => isToday && s.startAt <= now && now < `${date}T${endOf(timeOf(s.startAt))}:00`;
  const sel = list.find((s) => s.slotId === selectedId) ?? null;
  const next = isToday ? booked.find((s) => s.startAt > now) : undefined;

  function rowState(s: DirectorSlot) {
    if (current(s)) return <Pill cls="emr-pill-rec">진료중</Pill>;
    if (s.reservation) return isPast(s.startAt) ? <Pill cls="emr-pill-done">완료</Pill> : <StatusPill status={s.reservation.status} />;
    if (!s.isOpen) return <Pill cls="emr-pill-done">닫힘</Pill>;
    return <span style={{ color: 'var(--emr-text-mute)' }}>빈 시간</span>;
  }

  return (
    <>
      <dl className="emr-sum" aria-label={`${korDate(date)} 요약`}>
        <div><dt>진료 예약</dt><dd>{booked.length}<small>건</small></dd></div>
        <div className="is-brand"><dt>확정</dt><dd>{booked.filter((s) => s.reservation!.status === 'CONFIRMED').length}<small>건</small></dd></div>
        <div className="is-warn"><dt>승인 대기</dt><dd>{booked.filter((s) => s.reservation!.status === 'REQUESTED').length}<small>건</small></dd></div>
        <div><dt>빈 시간</dt><dd>{list.filter((s) => s.isOpen && !s.reservation && !isPast(s.startAt)).length}<small>개</small></dd></div>
        <div><dt>닫은 시간</dt><dd>{list.filter((s) => !s.isOpen).length}<small>개</small></dd></div>
        <div><dt>다음 진료</dt><dd>{next ? timeOf(next.startAt) : '—'}<small>{next?.reservation ? next.reservation.petName : ''}</small></dd></div>
      </dl>

      <div className="emr-cols emr-cols--3">
        <DateListPanel value={date} onChange={setDate} />

        <Panel title={<>진료 목록 <small>— {vet ? `${vet.name} ${vet.title}` : ''} · {korDate(date)}</small></>} right={<small>{booked.length} / {list.length}</small>}>
          <div className="emr-toolbar">
            <button className="emr-btn" type="button" onClick={load}><Icon name="refresh" />새로고침</button>
            <span className="emr-toolbar__spacer" />
            <Link to={`/app/director/slots?date=${date}`} className="emr-btn"><Icon name="grid" />진료 시간 관리</Link>
          </div>
          {error ? <EmrError message={error} onRetry={load} /> : !slots ? <EmrLoading /> : list.length === 0 ? (
            <div className="emr-empty">이 날은 진료가 없습니다.</div>
          ) : (
            <div className="emr-scroll">
              <table className="emr-table">
                <thead><tr><th>시간</th><th className="center">상태</th><th>환자</th><th>종 / 나이</th><th>진료</th><th>보호자</th><th>연락처</th></tr></thead>
                <tbody>
                  {list.map((s) => {
                    const r = s.reservation;
                    const lunchGap = timeOf(s.startAt) === clinic.hours.lunchEnd;
                    return [
                      lunchGap && <tr key={`l-${s.slotId}`} className="is-muted"><td colSpan={7} className="center" style={{ background: '#f6f8f5' }}>점심시간 {clinic.hours.lunchStart}–{clinic.hours.lunchEnd}</td></tr>,
                      <tr key={s.slotId} data-clickable={r ? true : undefined}
                        className={`${s.slotId === selectedId ? 'selected' : ''}${(!r && !current(s)) || (isPast(s.startAt) && !current(s)) ? ' is-muted' : ''}`}
                        tabIndex={r ? 0 : -1} onClick={() => r && setSelectedId(s.slotId)}
                        onKeyDown={(e) => { if (r && e.key === 'Enter') setSelectedId(s.slotId); }}>
                        <td className="mono">{timeOf(s.startAt)}~{endOf(timeOf(s.startAt))}</td>
                        <td className="center">{rowState(s)}</td>
                        <td>{r ? <b>{r.petName}</b> : ''}</td>
                        <td>{r ? `${SPECIES_LABEL[r.petSpecies]} / ${r.petAge}세` : ''}</td>
                        <td><TypeTag type={s.visitType} />{s.isEvent && r && <> <span className="emr-pill emr-pill-event">할인</span></>}</td>
                        <td>{r?.ownerName ?? ''}</td>
                        <td className="num">{r?.ownerPhone ?? ''}</td>
                      </tr>,
                    ];
                  })}
                </tbody>
              </table>
            </div>
          )}
          <p className="emr-note">예약된 행을 누르면 환자 정보가 보입니다. 휴진·수술 일정은 「진료 시간 관리」에서 시간을 닫으세요.</p>
        </Panel>

        <div className="emr-stack">
          <Panel title="환자 정보">
            {!sel?.reservation ? <div className="emr-empty">예약된 진료를 선택하세요.</div> : (
              <>
                <div className="emr-patient">
                  <SpeciesAvatar species={sel.reservation.petSpecies} />
                  <div>
                    <div className="emr-patient__name">{sel.reservation.petName}</div>
                    <div className="emr-patient__sub">{SPECIES_LABEL[sel.reservation.petSpecies]} · {sel.reservation.petAge}세 · 환자번호 P-{String(sel.reservation.petId).padStart(5, '0')}</div>
                  </div>
                </div>
                <dl className="emr-body">
                  <div className="emr-field"><dt>진료 일시</dt><dd>{korDate(date)} {timeOf(sel.startAt)}</dd></div>
                  <div className="emr-field"><dt>진료 항목</dt><dd><TypeTag type={sel.visitType} /></dd></div>
                  <div className="emr-field"><dt>예약 상태</dt><dd>{current(sel) ? <Pill cls="emr-pill-rec">진료중</Pill> : <StatusPill status={sel.reservation.status} />}</dd></div>
                  <div className="emr-field"><dt>보호자</dt><dd>{sel.reservation.ownerName}</dd></div>
                  <div className="emr-field"><dt>연락처</dt><dd>{sel.reservation.ownerPhone}</dd></div>
                  <div className="emr-field"><dt>예약 번호</dt><dd>#{sel.reservation.reservationId}</dd></div>
                  <div className="emr-field"><dt>접수 시각</dt><dd>{sel.reservation.createdAt.replace('T', ' ').slice(0, 16)}</dd></div>
                  {sel.isEvent && <div className="emr-field"><dt>비고</dt><dd><span className="emr-pill emr-pill-event">예방접종 할인 이벤트</span></dd></div>}
                </dl>
                {sel.reservation.status === 'REQUESTED' && <p className="emr-note">승인 대기 중인 예약입니다. 접수 데스크(간호사)에서 확인 후 확정합니다.</p>}
              </>
            )}
          </Panel>
          <Panel title="오늘의 진료 흐름">
            <dl className="emr-body">
              <div className="emr-field"><dt>진료 시간</dt><dd>{clinic.hours.open}–{clinic.hours.close}</dd></div>
              <div className="emr-field"><dt>점심</dt><dd>{clinic.hours.lunchStart}–{clinic.hours.lunchEnd}</dd></div>
              <div className="emr-field"><dt>진료 단위</dt><dd>{clinic.slotMinutes}분 · 1:1</dd></div>
              <div className="emr-field"><dt>남은 예약</dt><dd>{booked.filter((s) => !isPast(s.startAt)).length}건</dd></div>
            </dl>
          </Panel>
        </div>
      </div>
    </>
  );
}
