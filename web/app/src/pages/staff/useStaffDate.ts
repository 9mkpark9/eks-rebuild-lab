import { bookingDays, firstClinicDay } from '../../lib/date';
import { navigate, useLocation } from '../../router';

/** 직원(간호사·원장) 화면의 선택 날짜. 탭을 옮겨도 유지되도록 ?date= 에 둔다. */
export function useStaffDate(): [string, (d: string) => void] {
  const { path, query } = useLocation();
  const q = query.get('date');
  const date = q && bookingDays().some((d) => d.ymd === q) ? q : firstClinicDay();
  return [date, (d: string) => navigate(`${path}?date=${d}`, { replace: true })];
}
