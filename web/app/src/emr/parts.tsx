import type { ReactNode } from 'react';
import { bookingDays, todayYmd, WEEK } from '../lib/date';
import type { Status, VisitType } from '../types';
import { Icon, TYPE_INFO } from '../ui';

/* EMR 화면 공통 부품 */

export function Panel({ title, right, children, className = '' }: { title: ReactNode; right?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={`emr-panel ${className}`}>
      <h2 className="emr-title"><span>{title}</span>{right && <span>{right}</span>}</h2>
      {children}
    </section>
  );
}

export const EmrLoading = () => <div className="emr-loading">불러오는 중…</div>;

export function EmrError({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="emr-error" role="alert">
      <Icon name="alert" className="icon--sm" />{message}
      {onRetry && <button className="emr-btn" type="button" onClick={onRetry} style={{ marginLeft: 'auto' }}>다시 시도</button>}
    </div>
  );
}

const STATUS: Record<Status, { label: string; cls: string }> = {
  REQUESTED: { label: '승인대기', cls: 'emr-pill-waiting' },
  CONFIRMED: { label: '확정', cls: 'emr-pill-active' },
  CANCELLED: { label: '취소', cls: 'emr-pill-done' },
};
export function StatusPill({ status }: { status: Status }) {
  const s = STATUS[status];
  return <span className={`emr-pill ${s.cls}`}>{s.label}</span>;
}
export const Pill = ({ cls, children }: { cls: string; children: ReactNode }) => <span className={`emr-pill ${cls}`}>{children}</span>;
export const TypeTag = ({ type }: { type: VisitType }) => <span className="emr-tag">{TYPE_INFO[type].name}</span>;

/** 진료일 목록 (오늘부터 14일). 행을 눌러 날짜를 고른다. */
export function DateListPanel({ value, onChange, title = '진료일' }: { value: string; onChange: (ymd: string) => void; title?: string }) {
  const today = todayYmd();
  return (
    <Panel title={title} className="emr-datelist-panel">
      <div className="emr-scroll">
        <table className="emr-table">
          <thead><tr><th>날짜</th><th className="center">요일</th><th>비고</th></tr></thead>
          <tbody>
            {bookingDays().map((d) => (
              <tr key={d.ymd}
                className={`${value === d.ymd ? 'selected' : ''}${d.closed ? ' is-muted' : ''}`}
                data-clickable={!d.closed || undefined}
                tabIndex={d.closed ? -1 : 0}
                aria-selected={value === d.ymd}
                onClick={() => !d.closed && onChange(d.ymd)}
                onKeyDown={(e) => { if (!d.closed && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); onChange(d.ymd); } }}>
                <td className="mono">{d.month}/{String(d.day).padStart(2, '0')}</td>
                <td className="center" style={{ color: d.weekday === 0 ? '#b91c1c' : d.weekday === 6 ? '#1d4ed8' : undefined }}>{WEEK[d.weekday]}</td>
                <td>{d.closed ? '휴진' : d.ymd === today ? <Pill cls="emr-pill-active">오늘</Pill> : ''}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Panel>
  );
}
