import { useCallback, useEffect, useRef, useState } from 'react';
import { api, ApiError, messageOf } from '../api';
import { DateStrip, TimePicker } from '../components/booking';
import { PetFormModal } from '../components/PetFormModal';
import { firstClinicDay, korDate, korTime, timeOf } from '../lib/date';
import { josa } from '../lib/text';
import { Link, useLocation } from '../router';
import type { Pet, Reservation, Slot, VisitType } from '../types';
import { EmptyState, ErrorBox, Icon, SPECIES_LABEL, SpeciesAvatar, Spinner, StatusBadge, TYPE_INFO, TypeBadge, useToast } from '../ui';

type Inline = { kind: 'pet' | 'slot' | 'general'; text: string } | null;
const TYPES = Object.keys(TYPE_INFO) as VisitType[];

export default function Reserve() {
  const { query } = useLocation();
  const toast = useToast();
  const [pets, setPets] = useState<Pet[] | null>(null);
  const [petsError, setPetsError] = useState<string | null>(null);
  const [petId, setPetId] = useState<number | null>(() => Number(query.get('pet')) || null);
  const [type, setType] = useState<VisitType | null>(() => {
    const t = query.get('type') as VisitType | null;
    return t && TYPES.includes(t) ? t : null;
  });
  const [date, setDate] = useState<string>(firstClinicDay);
  const [slots, setSlots] = useState<Slot[]>([]);
  const [slotsLoading, setSlotsLoading] = useState(false);
  const [slotsError, setSlotsError] = useState<string | null>(null);
  const [selected, setSelected] = useState<Slot | null>(null);
  const [inline, setInline] = useState<Inline>(null);
  const [submitting, setSubmitting] = useState(false);
  const [done, setDone] = useState<Reservation | null>(null);
  const [petModal, setPetModal] = useState(false);
  const reqSeq = useRef(0);

  const loadPets = useCallback(() => {
    setPetsError(null);
    api.pets().then((list) => {
      setPets(list);
      setPetId((cur) => (cur && list.some((p) => p.petId === cur) ? cur : list.length === 1 ? list[0].petId : null));
    }).catch((e) => setPetsError(messageOf(e)));
  }, []);
  useEffect(loadPets, [loadPets]);

  const loadSlots = useCallback(() => {
    if (!type || !date) return;
    const seq = ++reqSeq.current; // 늦게 도착한 이전 응답은 버린다
    setSlotsLoading(true);
    setSlotsError(null);
    api.slots(date, type)
      .then((list) => { if (seq === reqSeq.current) setSlots(list); })
      .catch((e) => { if (seq === reqSeq.current) setSlotsError(messageOf(e)); })
      .finally(() => { if (seq === reqSeq.current) setSlotsLoading(false); });
  }, [date, type]);
  useEffect(() => { setSelected(null); loadSlots(); }, [loadSlots]);

  const pet = pets?.find((p) => p.petId === petId) ?? null;
  const ready = !!(pet && type && selected);

  async function submit() {
    if (!pet || !selected) return;
    setSubmitting(true);
    setInline(null);
    try {
      const r = await api.createReservation(pet.petId, selected.slotId);
      setDone(r);
      toast('success', '예약 신청이 접수되었어요.');
      window.scrollTo({ top: 0, behavior: 'smooth' });
    } catch (e) {
      if (e instanceof ApiError && e.code === 'SLOT_TAKEN') {
        setInline({ kind: 'slot', text: messageOf(e) });
        setSelected(null);
        loadSlots();
        toast('error', '이미 예약된 시간이에요. 다른 시간을 골라 주세요.');
      } else if (e instanceof ApiError && e.code === 'PET_SAME_DAY') {
        setInline({ kind: 'pet', text: `${josa(pet.name, '은', '는')} ${korDate(date)}에 이미 예약이 있어요. 하루에 한 건만 예약할 수 있으니 다른 날짜를 고르거나 ‘내 예약’에서 변경해 주세요.` });
        toast('error', `${josa(pet.name, '은', '는')} 그날 이미 예약이 있어요.`);
      } else if (e instanceof ApiError && e.status === 404) {
        setInline({ kind: 'slot', text: '선택한 시간이 방금 닫혔어요. 다른 시간을 선택해 주세요.' });
        setSelected(null);
        loadSlots();
        toast('error', '선택한 시간이 닫혔어요.');
      } else {
        setInline({ kind: 'general', text: messageOf(e) });
        toast('error', '예약하지 못했어요. 잠시 후 다시 시도해 주세요.');
      }
    } finally {
      setSubmitting(false);
    }
  }

  if (done) {
    return (
      <div className="done card">
        <span className="done__icon"><Icon name="check" /></span>
        <h1 className="done__title">예약 신청이 접수되었어요</h1>
        <p className="done__desc">선택한 시간은 보호자님 앞으로 잡혀 있어요. 병원에서 확인하면 ‘예약 확정’으로 바뀝니다.</p>
        <dl className="summary-list summary-list--boxed">
          <div><dt>반려동물</dt><dd>{done.petName}</dd></div>
          <div><dt>진료 항목</dt><dd><TypeBadge type={done.visitType} /></dd></div>
          <div><dt>일시</dt><dd>{korDate(done.visitDate)} {korTime(timeOf(done.startAt))}</dd></div>
          <div><dt>담당 수의사</dt><dd>{done.vetName} {done.vetTitle}</dd></div>
          <div><dt>상태</dt><dd><StatusBadge status={done.status} /></dd></div>
        </dl>
        <div className="done__actions">
          <Link to="/app/reservations" className="btn btn--primary">내 예약 보기</Link>
          <button className="btn btn--outline" type="button" onClick={() => { setDone(null); setSelected(null); loadSlots(); }}>다른 예약 하기</button>
        </div>
      </div>
    );
  }

  return (
    <div className="reserve">
      <div className="reserve__main">
        <header className="page-head">
          <h1 className="page-head__title">온라인 예약</h1>
          <p className="page-head__desc">반려동물, 진료 항목, 날짜와 시간을 차례로 선택하세요. 모든 진료는 30분입니다.</p>
        </header>

        {/* 1. 반려동물 */}
        <section className="step-card" aria-labelledby="s1">
          <h2 className="step-card__title" id="s1"><span className="step-num">1</span>진료받을 반려동물</h2>
          {petsError && <ErrorBox message={petsError} onRetry={loadPets} />}
          {!pets && !petsError && <div className="option-grid">{[0, 1].map((i) => <span key={i} className="option-card is-skeleton" />)}</div>}
          {pets && pets.length === 0 && (
            <EmptyState icon="paw" title="등록된 반려동물이 없어요" desc="이름·종류·나이만 등록하면 바로 예약할 수 있어요."
              action={<button className="btn btn--primary btn--sm" type="button" onClick={() => setPetModal(true)}><Icon name="plus" />반려동물 등록</button>} />
          )}
          {pets && pets.length > 0 && (
            <div className="option-grid" role="radiogroup" aria-label="반려동물">
              {pets.map((p) => (
                <button key={p.petId} type="button" role="radio" aria-checked={petId === p.petId}
                  aria-label={`${p.name}, ${SPECIES_LABEL[p.species]} ${p.age}살`}
                  className={`option-card${petId === p.petId ? ' is-selected' : ''}`}
                  onClick={() => { setPetId(p.petId); if (inline?.kind === 'pet') setInline(null); }}>
                  <SpeciesAvatar species={p.species} />
                  <span className="option-card__text"><strong>{p.name}</strong><small>{SPECIES_LABEL[p.species]} · {p.age}살</small></span>
                  <span className="option-card__check"><Icon name="check" /></span>
                </button>
              ))}
              <button type="button" className="option-card option-card--add" onClick={() => setPetModal(true)}>
                <span className="pet-avatar pet-avatar--add"><Icon name="plus" /></span>
                <span className="option-card__text"><strong>새로 등록</strong><small>다른 아이 추가</small></span>
              </button>
            </div>
          )}
          {inline?.kind === 'pet' && <p className="form-error"><Icon name="alert" />{inline.text}</p>}
        </section>

        {/* 2. 진료 항목 */}
        <section className="step-card" aria-labelledby="s2">
          <h2 className="step-card__title" id="s2"><span className="step-num">2</span>진료 항목</h2>
          <div className="option-grid option-grid--3" role="radiogroup" aria-label="진료 항목">
            {TYPES.map((t) => {
              const info = TYPE_INFO[t];
              return (
                <button key={t} type="button" role="radio" aria-checked={type === t} aria-label={`${info.name}: ${info.desc}`}
                  className={`option-card option-card--type tone-${info.tone}${type === t ? ' is-selected' : ''}`}
                  onClick={() => { setType(t); setInline(null); }}>
                  <span className="type-icon"><Icon name={info.icon} /></span>
                  <span className="option-card__text"><strong>{info.name}</strong><small>{info.desc}</small></span>
                  <span className="option-card__check"><Icon name="check" /></span>
                </button>
              );
            })}
          </div>
        </section>

        {/* 3. 날짜 */}
        <section className="step-card" aria-labelledby="s3">
          <h2 className="step-card__title" id="s3"><span className="step-num">3</span>날짜<span className="step-card__hint">오늘부터 14일 · 일요일 휴진</span></h2>
          <DateStrip value={date} onChange={(d) => { setDate(d); if (inline?.kind !== 'general') setInline(null); }} />
        </section>

        {/* 4. 시간 */}
        <section className="step-card" aria-labelledby="s4">
          <h2 className="step-card__title" id="s4">
            <span className="step-num">4</span>시간
            {type && <button className="step-card__refresh" type="button" onClick={loadSlots} disabled={slotsLoading}><Icon name="refresh" />새로고침</button>}
          </h2>
          {inline?.kind === 'slot' && <p className="notice-box notice-box--danger" role="alert"><Icon name="alert" />{inline.text}</p>}
          {!type ? (
            <p className="placeholder-text"><Icon name="info" />진료 항목을 먼저 선택하면 {korDate(date)}의 예약 가능한 시간이 보여요.</p>
          ) : (
            <TimePicker date={date} slots={slots} loading={slotsLoading} error={slotsError} onRetry={loadSlots}
              selected={selected} onSelect={(s) => { setSelected(s); if (inline?.kind === 'slot') setInline(null); }} />
          )}
        </section>
      </div>

      {/* 요약 */}
      <aside className="reserve__aside">
        <div className="summary card">
          <h2 className="summary__title">예약 내용</h2>
          <dl className="summary-list">
            <div><dt>반려동물</dt><dd>{pet ? pet.name : <span className="muted">선택 전</span>}</dd></div>
            <div><dt>진료 항목</dt><dd>{type ? TYPE_INFO[type].name : <span className="muted">선택 전</span>}</dd></div>
            <div><dt>날짜</dt><dd>{korDate(date)}</dd></div>
            <div><dt>시간</dt><dd>{selected ? korTime(timeOf(selected.startAt)) : <span className="muted">선택 전</span>}</dd></div>
            <div><dt>담당 수의사</dt><dd>{selected ? `${selected.vetName} ${selected.vetTitle}` : <span className="muted">—</span>}</dd></div>
          </dl>
          {(inline?.kind === 'general' || inline?.kind === 'pet') && <p className="form-error" role="alert"><Icon name="alert" />{inline.text}</p>}
          <button className="btn btn--accent btn--lg btn--block" type="button" disabled={!ready || submitting} onClick={submit}>
            {submitting ? <Spinner label="신청 중" /> : '예약 신청하기'}
          </button>
          <ul className="summary__notes">
            <li><Icon name="check" />신청 즉시 시간이 잡히고, 병원 확인 후 확정돼요.</li>
            <li><Icon name="check" />변경·취소는 ‘내 예약’에서 할 수 있어요.</li>
          </ul>
        </div>
      </aside>

      {/* 모바일 하단 바 */}
      <div className={`reserve-bar${ready ? ' is-ready' : ''}`}>
        <p className="reserve-bar__text">
          {ready ? <><strong>{korDate(date)} {timeOf(selected!.startAt)}</strong><span>{pet!.name} · {TYPE_INFO[type!].name}</span></>
            : <span>{!pet ? '반려동물을 선택하세요' : !type ? '진료 항목을 선택하세요' : '시간을 선택하세요'}</span>}
        </p>
        <button className="btn btn--accent" type="button" disabled={!ready || submitting} onClick={submit}>{submitting ? <Spinner /> : '신청하기'}</button>
      </div>

      <PetFormModal open={petModal} pet={null} onClose={() => setPetModal(false)} onSaved={(p) => {
        setPets((xs) => [...(xs ?? []), p]);
        setPetId(p.petId);
        setPetModal(false);
        toast('success', `${josa(p.name, '이', '가')} 등록되었어요.`);
      }} />
    </div>
  );
}
