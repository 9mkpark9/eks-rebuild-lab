import clinic from '../../../clinic.config.json';

// 날짜는 'YYYY-MM-DD', 시각은 'YYYY-MM-DDTHH:mm:ss' 문자열(병원 현지 시각)로 주고받는다.
export const WEEK = ['일', '월', '화', '수', '목', '금', '토'];
const pad = (n: number) => String(n).padStart(2, '0');

export function toYmd(d: Date) {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}
export function fromYmd(ymd: string) {
  const [y, m, d] = ymd.split('-').map(Number);
  return new Date(y, m - 1, d);
}
export function nowIso() {
  const d = new Date();
  return `${toYmd(d)}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}
export const todayYmd = () => toYmd(new Date());
export const weekdayOf = (ymd: string) => fromYmd(ymd).getDay();
export const isClosedDay = (ymd: string) => clinic.hours.closedDays.includes(weekdayOf(ymd));
export const timeOf = (startAt: string) => startAt.slice(11, 16);
export const dateOf = (startAt: string) => startAt.slice(0, 10);
export const isPast = (startAt: string) => startAt <= nowIso();

/** 10월 20일 (화) */
export function korDate(ymd: string) {
  const d = fromYmd(ymd);
  return `${d.getMonth() + 1}월 ${d.getDate()}일 (${WEEK[d.getDay()]})`;
}
/** 10.20 (화) */
export function shortDate(ymd: string) {
  const d = fromYmd(ymd);
  return `${d.getMonth() + 1}.${d.getDate()} (${WEEK[d.getDay()]})`;
}
/** 오후 2:30 */
export function korTime(hhmm: string) {
  const [h, m] = hhmm.split(':').map(Number);
  return `${h < 12 ? '오전' : '오후'} ${h % 12 === 0 ? 12 : h % 12}:${pad(m)}`;
}

export interface BookingDay { ymd: string; day: number; month: number; weekday: number; closed: boolean; isToday: boolean }

/** 오늘부터 예약 가능 기간(14일)의 날짜 */
export function bookingDays(count = clinic.bookingDays): BookingDay[] {
  const base = new Date();
  base.setHours(0, 0, 0, 0);
  return Array.from({ length: count }, (_, i) => {
    const d = new Date(base);
    d.setDate(d.getDate() + i);
    const ymd = toYmd(d);
    return { ymd, day: d.getDate(), month: d.getMonth() + 1, weekday: d.getDay(), closed: isClosedDay(ymd), isToday: i === 0 };
  });
}

/** 첫 진료일 (오늘이 휴진이면 다음 진료일) */
export function firstClinicDay() {
  return bookingDays().find((d) => !d.closed)?.ymd ?? todayYmd();
}

/** 하루의 진료 시각 목록 (30분 단위, 점심 제외) */
export function clinicTimes() {
  const toMin = (s: string) => { const [h, m] = s.split(':').map(Number); return h * 60 + m; };
  const { open, close, lunchStart, lunchEnd } = clinic.hours;
  const out: string[] = [];
  for (let m = toMin(open); m < toMin(close); m += clinic.slotMinutes) {
    if (m >= toMin(lunchStart) && m < toMin(lunchEnd)) continue;
    out.push(`${pad(Math.floor(m / 60))}:${pad(m % 60)}`);
  }
  return out;
}
