import { useCallback, useEffect, useState } from 'react';
import clinic from '../../../../clinic.config.json';
import { api, messageOf } from '../../api';
import { useAuth } from '../../auth';
import { DateListPanel, EmrError, EmrLoading, Panel, Pill, StatusPill, TypeTag } from '../../emr/parts';
import { isPast, korDate, timeOf } from '../../lib/date';
import { myVet } from '../../lib/roles';
import type { DirectorSlot } from '../../types';
import { ConfirmDialog, Icon, useToast } from '../../ui';
import { useStaffDate } from '../staff/useStaffDate';

/** 원장 전용: 내 진료 시간 열기·닫기 (휴진·수술 일정) */
export default function DirectorSlots() {
  const toast = useToast();
  const { user } = useAuth();
  const vet = myVet(user);
  const [date, setDate] = useStaffDate();
  const [slots, setSlots] = useState<DirectorSlot[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busyIds, setBusyIds] = useState<Set<number>>(new Set());
  const [bulk, setBulk] = useState<null | 'close' | 'open'>(null);
  const [bulkRunning, setBulkRunning] = useState(false);

  const load = useCallback(() => {
    setError(null);
    api.directorSchedule(date).then(setSlots).catch((e) => setError(messageOf(e)));
  }, [date]);
  useEffect(() => { setSlots(null); load(); }, [load]);

  async function setOpen(s: DirectorSlot, isOpen: boolean) {
    setBusyIds((x) => new Set(x).add(s.slotId));
    try {
      await api.setMySlotOpen(s.slotId, isOpen);
      setSlots((xs) => xs && xs.map((x) => (x.slotId === s.slotId ? { ...x, isOpen } : x)));
      return true;
    } catch (e) {
      toast('error', messageOf(e));
      return false;
    } finally {
      setBusyIds((x) => { const n = new Set(x); n.delete(s.slotId); return n; });
    }
  }

  async function runBulk() {
    if (!slots || !bulk) return;
    const open = bulk === 'open';
    setBulkRunning(true);
    let ok = 0;
    for (const s of slots.filter((x) => !x.reservation && !isPast(x.startAt) && x.isOpen !== open)) if (await setOpen(s, open)) ok++;
    setBulkRunning(false);
    setBulk(null);
    toast('success', open ? `${ok}개 시간을 열었습니다.` : `${ok}개 시간을 닫았습니다. 이미 잡힌 예약은 그대로 남아 있습니다.`);
  }

  const list = slots ?? [];
  const booked = list.filter((s) => s.reservation).length;
  const closed = list.filter((s) => !s.isOpen).length;

  return (
    <>
      <dl className="emr-sum" aria-label={`${korDate(date)} 요약`}>
        <div><dt>내 진료 시간</dt><dd>{list.length}<small>개</small></dd></div>
        <div className="is-brand"><dt>예약 받는 중</dt><dd>{list.filter((s) => s.isOpen && !s.reservation && !isPast(s.startAt)).length}<small>개</small></dd></div>
        <div><dt>예약 있음</dt><dd>{booked}<small>건</small></dd></div>
        <div className="is-warn"><dt>닫힘</dt><dd>{closed}<small>개</small></dd></div>
        <div><dt>지난 시간</dt><dd>{list.filter((s) => isPast(s.startAt)).length}<small>개</small></dd></div>
        <div><dt>담당</dt><dd style={{ fontSize: 17 }}>{vet ? `${vet.name} ${vet.title}` : '—'}</dd></div>
      </dl>

      <div className="emr-cols emr-cols--side">
        <DateListPanel value={date} onChange={setDate} />

        <Panel title={<>진료 시간표 <small>— {korDate(date)}</small></>} right={<small>본인 진료만 변경 가능</small>}>
          <div className="emr-toolbar">
            <button className="emr-btn" type="button" onClick={load}><Icon name="refresh" />새로고침</button>
            <span className="emr-toolbar__spacer" />
            <button className="emr-btn" type="button" onClick={() => setBulk('open')} disabled={!slots || bulkRunning}>모두 열기</button>
            <button className="emr-btn emr-btn-danger" type="button" onClick={() => setBulk('close')} disabled={!slots || bulkRunning}><Icon name="lock" />이 날 휴진 처리</button>
          </div>
          {error ? <EmrError message={error} onRetry={load} /> : !slots ? <EmrLoading /> : list.length === 0 ? (
            <div className="emr-empty">이 날은 진료 시간이 없습니다.</div>
          ) : (
            <div className="emr-scroll">
              <table className="emr-table">
                <thead><tr><th>시간</th><th>진료 항목</th><th className="center">예약 받기</th><th>예약</th><th className="center">설정</th></tr></thead>
                <tbody>
                  {list.map((s) => {
                    const t = timeOf(s.startAt);
                    const past = isPast(s.startAt);
                    const r = s.reservation;
                    return [
                      t === clinic.hours.lunchEnd && <tr key={`l-${s.slotId}`} className="is-muted"><td colSpan={5} className="center" style={{ background: '#f6f8f5' }}>점심시간 {clinic.hours.lunchStart}–{clinic.hours.lunchEnd}</td></tr>,
                      <tr key={s.slotId} className={past ? 'is-muted' : ''}>
                        <td className="mono">{t}</td>
                        <td><TypeTag type={s.visitType} />{s.isEvent && <> <span className="emr-pill emr-pill-event">할인</span></>}</td>
                        <td className="center">{past ? <Pill cls="emr-pill-done">지남</Pill> : s.isOpen ? <Pill cls="emr-pill-active">열림</Pill> : <Pill cls="emr-pill-rec">닫힘</Pill>}</td>
                        <td>{r ? <><b>{r.petName}</b> <StatusPill status={r.status} /></> : <span style={{ color: 'var(--emr-text-mute)' }}>—</span>}</td>
                        <td className="center">
                          {r ? <span style={{ color: 'var(--emr-text-mute)' }}>예약 있음</span> : (
                            <button className={`emr-btn${s.isOpen ? '' : ' emr-btn-primary'}`} type="button" disabled={past || busyIds.has(s.slotId) || bulkRunning}
                              onClick={() => setOpen(s, !s.isOpen)} aria-label={`${t} ${s.isOpen ? '닫기' : '열기'}`}>
                              {s.isOpen ? '닫기' : '열기'}
                            </button>
                          )}
                        </td>
                      </tr>,
                    ];
                  })}
                </tbody>
              </table>
            </div>
          )}
          <p className="emr-note">닫으면 보호자 예약 화면에서 그 시간이 「마감」으로 보입니다. 이미 잡힌 예약은 닫아도 취소되지 않으니 접수 데스크에 연락을 부탁하세요.</p>
        </Panel>
      </div>

      <ConfirmDialog
        open={!!bulk}
        title={bulk === 'close' ? `${korDate(date)} 휴진 처리` : `${korDate(date)} 모든 시간 열기`}
        message={bulk === 'close'
          ? <p>내 빈 진료 시간을 모두 닫아 새 예약을 막습니다. <b>이미 잡힌 예약 {booked}건은 그대로 남습니다.</b></p>
          : <p>닫혀 있는 내 빈 시간을 모두 다시 엽니다.</p>}
        confirmLabel={bulk === 'close' ? '휴진 처리' : '모두 열기'}
        danger={bulk === 'close'}
        busy={bulkRunning}
        onConfirm={runBulk}
        onClose={() => !bulkRunning && setBulk(null)}
      />
    </>
  );
}
