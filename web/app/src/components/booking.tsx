import { useMemo, useRef, useState } from 'react';
import clinic from '../../../clinic.config.json';
import { bookingDays, clinicTimes, isPast, korTime, timeOf, todayYmd, WEEK, type BookingDay } from '../lib/date';
import type { Slot } from '../types';
import { EmptyState, ErrorBox, Icon } from '../ui';

/* ---------- 날짜 선택 (오늘부터 14일, 휴진일 비활성) ---------- */
export function DateStrip({ value, onChange, days = bookingDays(), label = '날짜 선택' }: {
  value: string | null; onChange: (ymd: string) => void; days?: BookingDay[]; label?: string;
}) {
  const scroller = useRef<HTMLDivElement>(null);
  const scroll = (dir: number) => scroller.current?.scrollBy({ left: dir * 320, behavior: 'smooth' });
  return (
    <div className="date-strip">
      <button className="date-strip__nav" type="button" onClick={() => scroll(-1)} aria-label="이전 날짜"><Icon name="chevron-left" /></button>
      <div className="date-strip__list" ref={scroller} role="radiogroup" aria-label={label}>
        {days.map((d, i) => {
          const showMonth = i === 0 || d.day === 1;
          return (
            <button
              key={d.ymd}
              type="button"
              role="radio"
              aria-checked={value === d.ymd}
              disabled={d.closed}
              className={`date-chip${value === d.ymd ? ' is-selected' : ''}${d.weekday === 6 ? ' is-sat' : ''}${d.closed ? ' is-closed' : ''}`}
              onClick={() => onChange(d.ymd)}
              aria-label={`${d.month}월 ${d.day}일 ${WEEK[d.weekday]}요일${d.closed ? ' 휴진' : ''}`}
            >
              <span className="date-chip__month">{showMonth ? `${d.month}월` : ' '}</span>
              <span className="date-chip__week">{WEEK[d.weekday]}</span>
              <span className="date-chip__day">{d.day}</span>
              <span className="date-chip__tag">{d.closed ? '휴진' : d.isToday ? '오늘' : ' '}</span>
            </button>
          );
        })}
      </div>
      <button className="date-strip__nav" type="button" onClick={() => scroll(1)} aria-label="다음 날짜"><Icon name="chevron-right" /></button>
    </div>
  );
}

/* ---------- 시간 선택 (비어 있는 슬롯만 선택 가능, 담당 수의사 선택) ---------- */
export function TimePicker({ date, slots, loading, error, onRetry, selected, onSelect }: {
  date: string;
  slots: Slot[];
  loading: boolean;
  error: string | null;
  onRetry: () => void;
  selected: Slot | null;
  onSelect: (s: Slot | null) => void;
}) {
  const [vetFilter, setVetFilter] = useState<number | null>(null);
  const times = useMemo(clinicTimes, []);
  const byTime = useMemo(() => {
    const m = new Map<string, Slot[]>();
    for (const s of slots) {
      const t = timeOf(s.startAt);
      m.set(t, [...(m.get(t) ?? []), s]);
    }
    return m;
  }, [slots]);
  const vets = useMemo(() => {
    const m = new Map<number, Slot>();
    slots.forEach((s) => { if (!m.has(s.vetId)) m.set(s.vetId, s); });
    return [...m.values()].sort((a, b) => a.vetId - b.vetId);
  }, [slots]);
  const visible = (t: string) => (byTime.get(t) ?? []).filter((s) => vetFilter == null || s.vetId === vetFilter);
  const availableCount = times.filter((t) => visible(t).length > 0).length;
  const isEvent = slots.some((s) => s.isEvent);
  const isToday = date === todayYmd();

  if (loading) {
    return (
      <div className="time-grid" aria-busy="true">
        {times.slice(0, 12).map((t) => <span key={t} className="time-chip is-skeleton" />)}
      </div>
    );
  }
  if (error) return <ErrorBox message={error} onRetry={onRetry} />;
  if (!slots.length) {
    return (
      <EmptyState
        icon="calendar"
        title="이 날은 예약 가능한 시간이 없어요"
        desc="모든 시간이 마감되었거나 이 진료 항목을 보지 않는 날입니다. 다른 날짜나 진료 항목을 선택해 보세요."
        action={<button className="btn btn--sm btn--outline" type="button" onClick={onRetry}><Icon name="refresh" />새로고침</button>}
      />
    );
  }

  function pickTime(t: string) {
    const cand = visible(t);
    if (cand.length) onSelect(cand[0]);
  }
  function changeFilter(v: number | null) {
    setVetFilter(v);
    if (selected && v != null && selected.vetId !== v) onSelect(null);
  }

  // 점심시간을 기준으로 오전 진료와 오후 진료를 나눈다
  const lunch = clinic.hours.lunchStart;
  const groups = [
    { label: '오전 진료', items: times.filter((t) => t < lunch) },
    { label: '오후 진료', items: times.filter((t) => t >= lunch) },
  ];
  const sameTime = selected ? byTime.get(timeOf(selected.startAt)) ?? [] : [];

  return (
    <div className="time-picker">
      {isEvent && (
        <p className="notice-box notice-box--accent"><Icon name="sparkle" />예방접종 할인 기간의 이벤트 시간입니다. 같은 시간을 여러 보호자님이 동시에 신청하면 먼저 처리된 한 건만 예약돼요.</p>
      )}
      {vets.length > 1 && (
        <div className="vet-filter" role="radiogroup" aria-label="담당 수의사">
          <span className="vet-filter__label">담당 수의사</span>
          <button type="button" role="radio" aria-checked={vetFilter == null} className="chip" onClick={() => changeFilter(null)}>상관없음</button>
          {vets.map((v) => (
            <button key={v.vetId} type="button" role="radio" aria-checked={vetFilter === v.vetId} className="chip" onClick={() => changeFilter(v.vetId)}>
              {v.vetName} {v.vetTitle}
            </button>
          ))}
        </div>
      )}
      <p className="time-picker__count">예약 가능 <strong>{availableCount}</strong>개 시간 <span>· 30분 진료</span></p>
      {groups.map((g) => (
        <div key={g.label} className="time-group">
          <p className="time-group__label">{g.label}</p>
          <div className="time-grid" role="radiogroup" aria-label={`${g.label} 시간`}>
            {g.items.map((t) => {
              const cand = visible(t);
              const on = selected != null && timeOf(selected.startAt) === t;
              const passed = isToday && isPast(`${date}T${t}:00`);
              return (
                <button
                  key={t}
                  type="button"
                  role="radio"
                  aria-checked={on}
                  disabled={!cand.length}
                  className={`time-chip${on ? ' is-selected' : ''}`}
                  onClick={() => pickTime(t)}
                  aria-label={`${korTime(t)} ${cand.length ? '예약 가능' : passed ? '지난 시간' : '마감'}`}
                >
                  <span className="time-chip__time">{t}</span>
                  {!cand.length && <span className="time-chip__state">{passed ? '지남' : '마감'}</span>}
                </button>
              );
            })}
          </div>
        </div>
      ))}
      {selected && sameTime.length > 1 && (
        <div className="vet-choice">
          <p className="vet-choice__label">{timeOf(selected.startAt)}에 진료 가능한 수의사</p>
          <div className="vet-choice__list">
            {sameTime.map((s) => (
              <button key={s.slotId} type="button" className={`vet-option${s.slotId === selected.slotId ? ' is-selected' : ''}`} onClick={() => onSelect(s)} aria-pressed={s.slotId === selected.slotId}>
                <img src={`/assets/img/vet-${s.vetId}.svg`} alt="" width="36" height="36" />
                <span><strong>{s.vetName}</strong> {s.vetTitle}</span>
                {s.slotId === selected.slotId && <Icon name="check" />}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
