import { useCallback, useEffect, useState } from 'react';
import { api, ApiError, messageOf } from '../../api';
import { DateListPanel, EmrError, EmrLoading, Panel, StatusPill, TypeTag } from '../../emr/parts';
import { isPast, korDate, timeOf } from '../../lib/date';
import { shortNode } from '../../lib/text';
import type { AdminReservation, AdminSlot, Status } from '../../types';
import { Icon, SPECIES_LABEL, useToast } from '../../ui';
import { useStaffDate } from '../staff/useStaffDate';

type Filter = 'ALL' | Status;
const FILTERS: { key: Filter; label: string }[] = [
  { key: 'ALL', label: '전체' },
  { key: 'REQUESTED', label: '승인대기' },
  { key: 'CONFIRMED', label: '확정' },
  { key: 'CANCELLED', label: '취소' },
];

/** 간호사 전용: 날짜별 전체 예약 현황과 승인 (접수 데스크) */
export default function NurseReservations() {
  const toast = useToast();
  const [date, setDate] = useStaffDate();
  const [resv, setResv] = useState<AdminReservation[] | null>(null);
  const [slots, setSlots] = useState<AdminSlot[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<Filter>('ALL');
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [working, setWorking] = useState<Set<number>>(new Set());
  const [bulk, setBulk] = useState(false);
  const [updatedAt, setUpdatedAt] = useState('');

  const load = useCallback(() => {
    setError(null);
    Promise.all([api.adminReservations(date), api.adminSlots(date)])
      .then(([r, s]) => {
        setResv(r);
        setSlots(s);
        setUpdatedAt(new Date().toLocaleTimeString('ko-KR'));
        setSelectedId((cur) => (cur && r.some((x) => x.reservationId === cur) ? cur : r[0]?.reservationId ?? null));
      })
      .catch((e) => setError(messageOf(e)));
  }, [date]);
  useEffect(() => { setResv(null); load(); }, [load]);

  async function approve(id: number, quiet = false) {
    setWorking((s) => new Set(s).add(id));
    try {
      await api.approve(id);
      setResv((xs) => xs && xs.map((r) => (r.reservationId === id ? { ...r, status: 'CONFIRMED' } : r)));
      if (!quiet) toast('success', '예약을 확정했습니다.');
      return true;
    } catch (e) {
      toast('error', messageOf(e));
      if (e instanceof ApiError && e.status === 409) load();
      return false;
    } finally {
      setWorking((s) => { const n = new Set(s); n.delete(id); return n; });
    }
  }
  async function approveAll() {
    if (!resv) return;
    setBulk(true);
    let ok = 0;
    for (const r of resv.filter((x) => x.status === 'REQUESTED')) if (await approve(r.reservationId, true)) ok++;
    setBulk(false);
    toast('success', `${ok}건을 확정했습니다.`);
  }

  const list = resv ?? [];
  const count = (s: Status) => list.filter((r) => r.status === s).length;
  const shown = list.filter((r) => filter === 'ALL' || r.status === filter);
  const sel = list.find((r) => r.reservationId === selectedId) ?? null;
  const openEmpty = slots.filter((s) => s.isOpen && !s.reservationId && !isPast(s.startAt)).length;
  const byWas = Object.entries(list.reduce<Record<string, number>>((m, r) => { m[r.servedBy] = (m[r.servedBy] ?? 0) + 1; return m; }, {})).sort();

  return (
    <>
      <dl className="emr-sum" aria-label={`${korDate(date)} 요약`}>
        <div><dt>활성 예약</dt><dd>{count('REQUESTED') + count('CONFIRMED')}<small>건</small></dd></div>
        <div className="is-warn"><dt>승인 대기</dt><dd>{count('REQUESTED')}<small>건</small></dd></div>
        <div className="is-brand"><dt>예약 확정</dt><dd>{count('CONFIRMED')}<small>건</small></dd></div>
        <div><dt>취소</dt><dd>{count('CANCELLED')}<small>건</small></dd></div>
        <div><dt>남은 시간</dt><dd>{openEmpty}<small>/ {slots.length}</small></dd></div>
        <div><dt>닫은 시간</dt><dd>{slots.filter((s) => !s.isOpen).length}<small>개</small></dd></div>
      </dl>

      <div className="emr-cols emr-cols--3">
        <DateListPanel value={date} onChange={setDate} />

        <Panel title={<>예약 목록 <small>— {korDate(date)}</small></>} right={<small>{shown.length}건 · 갱신 {updatedAt}</small>}>
          <div className="emr-toolbar">
            <span className="emr-toolbar__label">상태</span>
            {FILTERS.map((f) => (
              <button key={f.key} type="button" className="emr-btn" data-active={filter === f.key} onClick={() => setFilter(f.key)}>
                {f.label} ({f.key === 'ALL' ? list.length : count(f.key)})
              </button>
            ))}
            <span className="emr-toolbar__spacer" />
            <button className="emr-btn" type="button" onClick={load}><Icon name="refresh" />새로고침</button>
            <button className="emr-btn emr-btn-primary" type="button" disabled={!count('REQUESTED') || bulk} onClick={approveAll}>
              <Icon name="check" />{bulk ? '처리 중…' : `일괄 승인 (${count('REQUESTED')})`}
            </button>
          </div>
          {error ? <EmrError message={error} onRetry={load} /> : !resv ? <EmrLoading /> : shown.length === 0 ? (
            <div className="emr-empty">해당하는 예약이 없습니다.</div>
          ) : (
            <div className="emr-scroll">
              <table className="emr-table">
                <thead>
                  <tr><th className="center">No</th><th>시간</th><th>수의사</th><th>진료</th><th>환자</th><th>종</th><th>보호자</th><th>연락처</th><th className="center">상태</th><th>처리 WAS</th><th className="center">승인</th></tr>
                </thead>
                <tbody>
                  {shown.map((r, i) => (
                    <tr key={r.reservationId} data-clickable className={`${r.reservationId === selectedId ? 'selected' : ''}${r.status === 'CANCELLED' ? ' is-muted is-strike' : ''}`}
                      onClick={() => setSelectedId(r.reservationId)} tabIndex={0}
                      onKeyDown={(e) => { if (e.key === 'Enter') setSelectedId(r.reservationId); }}>
                      <td className="center num">{i + 1}</td>
                      <td className="mono">{timeOf(r.startAt)}</td>
                      <td>{r.vetName}</td>
                      <td><TypeTag type={r.visitType} /></td>
                      <td className="strike"><b>{r.petName}</b></td>
                      <td>{SPECIES_LABEL[r.petSpecies]}</td>
                      <td className="strike">{r.ownerName}</td>
                      <td className="num">{r.ownerPhone}</td>
                      <td className="center"><StatusPill status={r.status} /></td>
                      <td><code title={r.servedBy}>{shortNode(r.servedBy)}</code></td>
                      <td className="center">
                        {r.status === 'REQUESTED' && (
                          <button className="emr-btn emr-btn-primary" type="button" disabled={working.has(r.reservationId) || bulk}
                            onClick={(e) => { e.stopPropagation(); approve(r.reservationId); }}>승인</button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <p className="emr-note">행을 누르면 오른쪽에 상세가 보입니다. 승인하면 보호자 화면에 「예약 확정」으로 바뀝니다.</p>
        </Panel>

        <div className="emr-stack">
          <Panel title="예약 상세">
            {!sel ? <div className="emr-empty">예약을 선택하세요.</div> : (
              <div className="emr-body">
                <dl>
                  <div className="emr-field"><dt>예약번호</dt><dd>#{sel.reservationId}</dd></div>
                  <div className="emr-field"><dt>진료 일시</dt><dd>{korDate(sel.visitDate)} {timeOf(sel.startAt)}</dd></div>
                  <div className="emr-field"><dt>담당</dt><dd>{sel.vetName} {sel.vetTitle}</dd></div>
                  <div className="emr-field"><dt>진료 항목</dt><dd><TypeTag type={sel.visitType} />{sel.isEvent && <> <span className="emr-pill emr-pill-event">할인 이벤트</span></>}</dd></div>
                  <div className="emr-field"><dt>환자</dt><dd>{sel.petName} ({SPECIES_LABEL[sel.petSpecies]})</dd></div>
                  <div className="emr-field"><dt>보호자</dt><dd>{sel.ownerName} <small style={{ fontWeight: 400 }}>({sel.ownerLoginId})</small></dd></div>
                  <div className="emr-field"><dt>연락처</dt><dd>{sel.ownerPhone}</dd></div>
                  <div className="emr-field"><dt>접수 시각</dt><dd>{sel.createdAt.replace('T', ' ').slice(0, 16)}</dd></div>
                  <div className="emr-field"><dt>상태</dt><dd><StatusPill status={sel.status} /></dd></div>
                  <div className="emr-field"><dt>처리 WAS</dt><dd><code>{sel.servedBy}</code></dd></div>
                </dl>
                <div style={{ display: 'flex', gap: 4, justifyContent: 'flex-end', marginTop: 8 }}>
                  <a className="emr-btn" href={`tel:${sel.ownerPhone.replace(/[^0-9]/g, '')}`}><Icon name="phone" />보호자 전화</a>
                  <button className="emr-btn emr-btn-primary" type="button" disabled={sel.status !== 'REQUESTED' || working.has(sel.reservationId)} onClick={() => approve(sel.reservationId)}>
                    <Icon name="check" />예약 승인
                  </button>
                </div>
              </div>
            )}
          </Panel>
          <Panel title="처리 WAS 분포" right={<small>served_by</small>}>
            <table className="emr-table">
              <thead><tr><th>WAS</th><th className="num">건수</th></tr></thead>
              <tbody>
                {byWas.length === 0 ? <tr><td colSpan={2} className="center">—</td></tr> : byWas.map(([n, c]) => (
                  <tr key={n}><td><code title={n}>{shortNode(n)}</code></td><td className="num">{c}</td></tr>
                ))}
              </tbody>
            </table>
          </Panel>
        </div>
      </div>
    </>
  );
}
