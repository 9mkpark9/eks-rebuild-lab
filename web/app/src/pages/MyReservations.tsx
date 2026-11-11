import { useCallback, useEffect, useRef, useState } from 'react';
import { api, ApiError, messageOf } from '../api';
import { DateStrip, TimePicker } from '../components/booking';
import { bookingDays, dateOf, fromYmd, isPast, korDate, korTime, timeOf, WEEK } from '../lib/date';
import { Link } from '../router';
import type { Reservation, Slot } from '../types';
import { ConfirmDialog, EmptyState, ErrorBox, Icon, Modal, PageLoading, SpeciesAvatar, Spinner, StatusBadge, TypeBadge, useToast } from '../ui';

export default function MyReservations() {
  const toast = useToast();
  const [list, setList] = useState<Reservation[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<'upcoming' | 'past'>('upcoming');
  const [changing, setChanging] = useState<Reservation | null>(null);
  const [cancelling, setCancelling] = useState<Reservation | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    setError(null);
    api.myReservations().then(setList).catch((e) => setError(messageOf(e)));
  }, []);
  useEffect(load, [load]);

  async function doCancel() {
    if (!cancelling) return;
    setBusy(true);
    try {
      await api.cancelReservation(cancelling.reservationId);
      toast('success', '예약을 취소했어요. 그 시간은 다른 보호자님께 열립니다.');
    } catch (e) {
      toast('error', messageOf(e));
    } finally {
      setBusy(false);
      setCancelling(null);
      load();
    }
  }

  if (error) return <ErrorBox message={error} onRetry={load} />;
  if (!list) return <PageLoading />;

  const active = (r: Reservation) => r.status !== 'CANCELLED' && !isPast(r.startAt);
  const upcoming = list.filter(active);
  const past = list.filter((r) => !active(r)).reverse();
  const shown = tab === 'upcoming' ? upcoming : past;

  return (
    <div className="stack-lg">
      <header className="page-head page-head--row">
        <div>
          <h1 className="page-head__title">내 예약</h1>
          <p className="page-head__desc">예약 상태를 확인하고 시간을 바꾸거나 취소할 수 있어요.</p>
        </div>
        <Link to="/app/reserve" className="btn btn--accent"><Icon name="plus" />새 예약</Link>
      </header>

      <div className="tabs" role="tablist" aria-label="예약 구분">
        <button role="tab" type="button" aria-selected={tab === 'upcoming'} className="tabs__tab" onClick={() => setTab('upcoming')}>다가오는 예약 <span>{upcoming.length}</span></button>
        <button role="tab" type="button" aria-selected={tab === 'past'} className="tabs__tab" onClick={() => setTab('past')}>지난·취소된 예약 <span>{past.length}</span></button>
      </div>

      {shown.length === 0 ? (
        <EmptyState icon="calendar" title={tab === 'upcoming' ? '다가오는 예약이 없어요' : '지난 예약이 없어요'}
          desc={tab === 'upcoming' ? '진료 시간 밖에도 온라인으로 예약할 수 있어요.' : undefined}
          action={tab === 'upcoming' ? <Link to="/app/reserve" className="btn btn--primary btn--sm">예약하러 가기</Link> : undefined} />
      ) : (
        <ul className="resv-list">
          {shown.map((r) => {
            const d = fromYmd(dateOf(r.startAt));
            const canEdit = active(r);
            return (
              <li key={r.reservationId} className={`resv-card${r.status === 'CANCELLED' ? ' is-cancelled' : ''}`}>
                <div className="resv-card__date">
                  <span>{d.getMonth() + 1}월</span>
                  <strong>{d.getDate()}</strong>
                  <span>{WEEK[d.getDay()]}요일</span>
                </div>
                <div className="resv-card__body">
                  <p className="resv-card__time">{korTime(timeOf(r.startAt))}<StatusBadge status={r.status} />{r.isEvent && <span className="badge badge--accent">할인 이벤트</span>}</p>
                  <p className="resv-card__meta">
                    <span><SpeciesAvatar species={r.petSpecies} size="sm" /><strong>{r.petName}</strong></span>
                    <TypeBadge type={r.visitType} />
                    <span className="muted"><Icon name="doctor" />{r.vetName} {r.vetTitle}</span>
                  </p>
                </div>
                {canEdit && (
                  <div className="resv-card__actions">
                    <button className="btn btn--sm btn--outline" type="button" onClick={() => setChanging(r)}><Icon name="edit" />변경</button>
                    <button className="btn btn--sm btn--danger" type="button" onClick={() => setCancelling(r)}>취소</button>
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      )}

      <ChangeModal resv={changing} onClose={() => setChanging(null)} onChanged={() => {
        setChanging(null);
        toast('success', '예약 시간을 변경했어요. 병원에서 다시 확인 후 확정합니다.');
        load();
      }} onStale={() => { setChanging(null); load(); }} />

      <ConfirmDialog
        open={!!cancelling}
        title="예약을 취소할까요?"
        message={cancelling && <>
          <p><strong>{korDate(dateOf(cancelling.startAt))} {korTime(timeOf(cancelling.startAt))}</strong> · {cancelling.petName}</p>
          <p className="muted">취소하면 이 시간은 바로 다른 보호자님께 열려 다시 잡지 못할 수 있어요.</p>
        </>}
        confirmLabel="예약 취소"
        danger
        busy={busy}
        onConfirm={doCancel}
        onClose={() => !busy && setCancelling(null)}
      />
    </div>
  );
}

function ChangeModal({ resv, onClose, onChanged, onStale }: {
  resv: Reservation | null; onClose: () => void; onChanged: () => void; onStale: () => void;
}) {
  const toast = useToast();
  const [date, setDate] = useState('');
  const [slots, setSlots] = useState<Slot[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<Slot | null>(null);
  const [inline, setInline] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const seq = useRef(0);

  useEffect(() => {
    if (!resv) return;
    const days = bookingDays();
    setDate(days.some((d) => d.ymd === resv.visitDate && !d.closed) ? resv.visitDate : days.find((d) => !d.closed)!.ymd);
    setInline(null);
  }, [resv]);

  const load = useCallback(() => {
    if (!resv || !date) return;
    const s = ++seq.current;
    setLoading(true);
    setError(null);
    setSelected(null);
    api.slots(date, resv.visitType)
      .then((l) => { if (s === seq.current) setSlots(l); })
      .catch((e) => { if (s === seq.current) setError(messageOf(e)); })
      .finally(() => { if (s === seq.current) setLoading(false); });
  }, [resv, date]);
  useEffect(load, [load]);

  async function submit() {
    if (!resv || !selected) return;
    setBusy(true);
    setInline(null);
    try {
      await api.changeReservation(resv.reservationId, selected.slotId);
      onChanged();
    } catch (e) {
      if (e instanceof ApiError && e.code === 'CANCELLED') {
        toast('error', messageOf(e));
        onStale();
      } else {
        // 변경 실패 시 서버가 전체를 되돌리므로 기존 예약은 그대로 남아 있다
        setInline(`${messageOf(e)} 기존 예약은 그대로 유지됩니다.`);
        if (e instanceof ApiError && (e.code === 'SLOT_TAKEN' || e.status === 404)) load();
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open={!!resv} title="예약 시간 변경" onClose={() => !busy && onClose()} size="lg" footer={
      <>
        <button className="btn btn--outline" type="button" onClick={onClose} disabled={busy}>닫기</button>
        <button className="btn btn--primary" type="button" onClick={submit} disabled={!selected || busy}>
          {busy ? <Spinner /> : selected ? `${timeOf(selected.startAt)} · 이 시간으로 변경` : '시간을 선택하세요'}
        </button>
      </>
    }>
      {resv && (
        <div className="stack">
          <div className="current-box">
            <span className="badge">현재 예약</span>
            <strong>{korDate(resv.visitDate)} {korTime(timeOf(resv.startAt))}</strong>
            <span className="muted">{resv.petName} · {resv.vetName} {resv.vetTitle}</span>
            <TypeBadge type={resv.visitType} />
          </div>
          {inline && <p className="notice-box notice-box--danger" role="alert"><Icon name="alert" />{inline}</p>}
          <DateStrip value={date} onChange={setDate} />
          <TimePicker date={date} slots={slots} loading={loading} error={error} onRetry={load} selected={selected} onSelect={setSelected} />
        </div>
      )}
    </Modal>
  );
}
