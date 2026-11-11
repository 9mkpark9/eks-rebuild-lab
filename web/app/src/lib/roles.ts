import clinic from '../../../clinic.config.json';
import type { Role, User } from '../types';

/** 역할별 첫 화면 */
export const ROLE_HOME: Record<Role, string> = { OWNER: '/app/', NURSE: '/app/nurse', DIRECTOR: '/app/director' };

const ROLE_NAME: Record<Role, string> = { OWNER: '보호자', NURSE: '간호사', DIRECTOR: '원장' };

/** 화면에 보일 직함: 보호자 · 간호사 · 대표원장/원장 */
export function roleLabel(role: Role, vetId?: number | null) {
  if (role === 'DIRECTOR' && vetId) return clinic.vets.find((v) => v.id === vetId)?.title ?? ROLE_NAME.DIRECTOR;
  return ROLE_NAME[role];
}
export const roleName = (role: Role) => ROLE_NAME[role];

/** 원장 계정이 맡은 수의사 정보 (clinic.config.json) */
export const myVet = (user: User | null) => clinic.vets.find((v) => v.id === user?.vetId) ?? null;
