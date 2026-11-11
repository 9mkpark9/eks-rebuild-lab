import { useCallback, useEffect, useState } from 'react';
import { api, messageOf } from '../../api';
import { DailyChart } from '../../components/DailyChart';
import { EmrError, EmrLoading, Panel } from '../../emr/parts';
import { korDate } from '../../lib/date';
import { shortNode } from '../../lib/text';
import type { DirectorStats as Stats } from '../../types';
import { Icon, TYPE_INFO } from '../../ui';

const pct = (a: number, b: number) => (b ? Math.round((a / b) * 100) : 0);

/** 원장 전용: 예약 가능 기간(14일) 병원 현황 */
export default function DirectorStats() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [updatedAt, setUpdatedAt] = useState('');

  const load = useCallback(() => {
    setError(null);
    api.directorStats()
      .then((s) => { setStats(s); setUpdatedAt(new Date().toLocaleTimeString('ko-KR')); })
      .catch((e) => setError(messageOf(e)));
  }, []);
  useEffect(load, [load]);

  if (error) return <EmrError message={error} onRetry={load} />;
  if (!stats) return <div className="emr-panel"><EmrLoading /></div>;

  const t = stats.totals;
  const first = stats.days[0]?.date;
  const last = stats.days[stats.days.length - 1]?.date;
  const maxVet = Math.max(1, ...stats.byVet.map((v) => v.active));
  const maxType = Math.max(1, ...stats.byType.map((x) => x.active));
  const wasTotal = stats.byWas.reduce((a, r) => a + r.count, 0);
  const wasAvg = stats.byWas.length ? wasTotal / stats.byWas.length : 0;
  const wasTop = Math.max(1, wasAvg * 1.25, ...stats.byWas.map((r) => r.count)) * 1.05;
  const at = (v: number) => `${(v / wasTop) * 100}%`;

  return (
    <>
      <dl className="emr-sum" aria-label="병원 현황 요약">
        <div><dt>예약률</dt><dd>{pct(t.active, t.slots)}<small>% ({t.active}/{t.slots})</small></dd></div>
        <div className="is-brand"><dt>예약 확정</dt><dd>{t.confirmed}<small>건</small></dd></div>
        <div className="is-warn"><dt>승인 대기</dt><dd>{t.requested}<small>건</small></dd></div>
        <div><dt>남은 시간</dt><dd>{t.open}<small>개</small></dd></div>
        <div><dt>닫은 시간</dt><dd>{t.closed}<small>개</small></dd></div>
        <div><dt>취소</dt><dd>{t.cancelled}<small>건</small></dd></div>
      </dl>

      <Panel title={<>날짜별 예약 <small>— {first && last ? `${korDate(first)} ~ ${korDate(last)}` : ''}</small></>}
        right={<button className="emr-btn" type="button" onClick={load}><Icon name="refresh" />새로고침 · {updatedAt}</button>}>
        <div className="emr-body"><DailyChart days={stats.days} /></div>
      </Panel>

      <div className="emr-cols emr-cols--2">
        <Panel title="수의사별 활성 예약">
          <div className="emr-scroll"><table className="emr-table">
            <thead><tr><th>수의사</th><th className="num">예약</th><th className="num">예약률</th><th style={{ width: '45%' }}>비교</th></tr></thead>
            <tbody>
              {stats.byVet.map((v) => (
                <tr key={v.vetId}>
                  <td><b>{v.vetName}</b> <span style={{ color: 'var(--emr-text-mute)' }}>{v.vetTitle}</span></td>
                  <td className="num">{v.active}</td>
                  <td className="num">{pct(v.active, v.slots)}%</td>
                  <td><div className="emr-bar"><span style={{ width: `${(v.active / maxVet) * 100}%` }} /></div></td>
                </tr>
              ))}
            </tbody>
          </table></div>
        </Panel>
        <Panel title="진료 항목별 활성 예약">
          <div className="emr-scroll"><table className="emr-table">
            <thead><tr><th>진료 항목</th><th className="num">예약</th><th className="num">비율</th><th style={{ width: '45%' }}>비교</th></tr></thead>
            <tbody>
              {stats.byType.map((x) => (
                <tr key={x.visitType}>
                  <td><b>{TYPE_INFO[x.visitType].name}</b></td>
                  <td className="num">{x.active}</td>
                  <td className="num">{pct(x.active, t.active)}%</td>
                  <td><div className="emr-bar"><span style={{ width: `${(x.active / maxType) * 100}%` }} /></div></td>
                </tr>
              ))}
            </tbody>
          </table></div>
        </Panel>
      </div>

      <Panel title="WAS별 예약 처리 건수 (served_by)" right={<small>8장 성공 기준: 평균 {wasAvg.toFixed(1)}건의 ±20% 이내</small>}>
        <div className="emr-scroll"><table className="emr-table">
          <thead><tr><th>WAS 인스턴스</th><th className="num">처리</th><th className="num">평균 대비</th><th className="center">판정</th><th style={{ width: '40%' }}>분포 (회색 띠 = 평균 ±20%, 세로선 = 평균)</th></tr></thead>
          <tbody>
            {stats.byWas.map((r) => {
              const dev = wasAvg ? ((r.count - wasAvg) / wasAvg) * 100 : 0;
              const ok = Math.abs(dev) <= 20;
              return (
                <tr key={r.servedBy}>
                  <td><code title={r.servedBy}>{shortNode(r.servedBy)}</code></td>
                  <td className="num">{r.count}</td>
                  <td className="num">{dev >= 0 ? '+' : ''}{dev.toFixed(1)}%</td>
                  <td className="center">{ok ? <span className="emr-ok"><Icon name="check-circle" className="icon--sm" /> 기준 이내</span> : <span className="emr-bad"><Icon name="alert" className="icon--sm" /> 벗어남</span>}</td>
                  <td>
                    <div className="emr-bar">
                      <span className="emr-bar__band" style={{ left: at(wasAvg * 0.8), width: at(wasAvg * 0.4) }} aria-hidden="true" />
                      <span style={{ width: at(r.count) }} />
                      <span className="emr-bar__avg" style={{ left: at(wasAvg) }} aria-hidden="true" />
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table></div>
      </Panel>
    </>
  );
}
