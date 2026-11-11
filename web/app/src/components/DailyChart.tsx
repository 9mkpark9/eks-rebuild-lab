import { useState } from 'react';
import { fromYmd, korDate, WEEK } from '../lib/date';
import type { DirectorStats } from '../types';

const pct = (a: number, b: number) => (b ? Math.round((a / b) * 100) : 0);
type Stats = DirectorStats;

/* ---------- 날짜별 누적 막대: 확정 + 승인 대기, 뒤에는 그날 받을 수 있는 시간 ---------- */
export function DailyChart({ days }: { days: Stats['days'] }) {
  const [hover, setHover] = useState<number | null>(null);
  const max = Math.max(1, ...days.map((d) => d.slots));
  const step = Math.ceil(max / 4);
  const ticks = [0, 1, 2, 3, 4].map((i) => i * step).filter((v) => v <= max + step / 2);
  const top = ticks[ticks.length - 1] || max;
  const h = (v: number) => `${(v / top) * 100}%`;
  const d = hover != null ? days[hover] : null;

  return (
    <figure className="viz">
      <ul className="viz-legend" aria-label="범례">
        <li><i className="viz-key viz-key--1" />예약 확정</li>
        <li><i className="viz-key viz-key--2" />승인 대기</li>
        <li><i className="viz-key viz-key--track" />받을 수 있는 시간</li>
      </ul>
      <div className="col-chart">
        <div className="col-chart__area">
          {ticks.map((v) => (
            <span key={v} className="col-chart__tick" style={{ bottom: h(v) }}><span>{v}</span></span>
          ))}
          <div className="col-chart__bars" style={{ gridTemplateColumns: `repeat(${days.length}, 1fr)` }}>
            {days.map((x, i) => {
              const cap = x.slots - x.closed;
              return (
                <button
                  key={x.date}
                  type="button"
                  className={`col${hover === i ? ' is-hover' : ''}`}
                  onMouseEnter={() => setHover(i)} onMouseLeave={() => setHover(null)}
                  onFocus={() => setHover(i)} onBlur={() => setHover(null)}
                  aria-label={`${korDate(x.date)}: 확정 ${x.confirmed}건, 승인 대기 ${x.requested}건, 받을 수 있는 시간 ${cap}개`}
                >
                  <span className="col__track" style={{ height: h(cap) }} />
                  {x.confirmed + x.requested > 0 && (
                    <span className="col__stack" style={{ height: h(x.confirmed + x.requested) }}>
                      {x.requested > 0 && <span className="col__seg col__seg--2" style={{ flexGrow: x.requested }} />}
                      {x.confirmed > 0 && <span className="col__seg col__seg--1" style={{ flexGrow: x.confirmed }} />}
                    </span>
                  )}
                </button>
              );
            })}
          </div>
          {d && hover != null && (
            <div className="viz-tip" role="status" style={{ left: `${((hover + 0.5) / days.length) * 100}%` }}>
              <strong>{korDate(d.date)}{d.isEvent ? ' · 할인 이벤트' : ''}</strong>
              <span><i className="viz-key viz-key--1" />확정 {d.confirmed}건</span>
              <span><i className="viz-key viz-key--2" />승인 대기 {d.requested}건</span>
              <span className="muted">받을 수 있는 시간 {d.slots - d.closed}개 · 예약률 {pct(d.confirmed + d.requested, d.slots)}%</span>
            </div>
          )}
        </div>
        <div className="col-chart__x" style={{ gridTemplateColumns: `repeat(${days.length}, 1fr)` }} aria-hidden="true">
          {days.map((x) => {
            const dt = fromYmd(x.date);
            return (
              <span key={x.date} className={x.isEvent ? 'is-event' : ''}>
                {dt.getDate()}<small>{WEEK[dt.getDay()]}</small>{x.isEvent && <em>할인</em>}
              </span>
            );
          })}
        </div>
      </div>
      <details className="viz-table">
        <summary>표로 보기</summary>
        <div className="table-wrap">
          <table className="data-table data-table--compact">
            <thead><tr><th>날짜</th><th>확정</th><th>승인 대기</th><th>취소</th><th>받을 수 있는 시간</th><th>예약률</th></tr></thead>
            <tbody>
              {days.map((x) => (
                <tr key={x.date}>
                  <td data-label="날짜">{korDate(x.date)}{x.isEvent && <span className="badge badge--accent badge--tiny">할인</span>}</td>
                  <td data-label="확정" className="mono">{x.confirmed}</td>
                  <td data-label="승인 대기" className="mono">{x.requested}</td>
                  <td data-label="취소" className="mono">{x.cancelled}</td>
                  <td data-label="받을 수 있는 시간" className="mono">{x.slots - x.closed} / {x.slots}</td>
                  <td data-label="예약률" className="mono">{pct(x.confirmed + x.requested, x.slots)}%</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </details>
    </figure>
  );
}
