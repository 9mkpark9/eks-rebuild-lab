// API 응답 형식 (6장의 API 표). WAS(Spring Boot)도 같은 JSON 키를 쓴다.
export type Role = 'OWNER' | 'NURSE' | 'DIRECTOR'; // 보호자 · 간호사(접수) · 원장(수의사)
export type Species = 'DOG' | 'CAT' | 'ETC';
export type VisitType = 'GENERAL' | 'VACCINE' | 'CHECKUP';
export type Status = 'REQUESTED' | 'CONFIRMED' | 'CANCELLED';
export type NoticeCategory = 'NOTICE' | 'EVENT' | 'CLOSED';

export interface User {
  userId: number;
  loginId: string;
  name: string;
  role: Role;
  vetId: number | null; // 원장 계정이 맡은 수의사
}

export interface Pet {
  petId: number;
  name: string;
  species: Species;
  age: number;
}

export interface Slot {
  slotId: number;
  vetId: number;
  vetName: string;
  vetTitle: string;
  startAt: string; // YYYY-MM-DDTHH:mm:ss (병원 현지 시각)
  visitType: VisitType;
  isEvent: boolean;
}

export interface Reservation {
  reservationId: number;
  petId: number;
  petName: string;
  petSpecies: Species;
  slotId: number;
  startAt: string;
  visitDate: string;
  visitType: VisitType;
  vetId: number;
  vetName: string;
  vetTitle: string;
  isEvent: boolean;
  status: Status;
  servedBy: string;
  createdAt: string;
}

export interface AdminReservation extends Reservation {
  ownerName: string;
  ownerLoginId: string;
  ownerPhone: string;
}

export interface AdminSlot extends Slot {
  isOpen: boolean;
  reservationId: number | null;
  petName: string | null;
  status: Status | null;
}

export interface Notice {
  noticeId: number;
  category: NoticeCategory;
  title: string;
  pinned: boolean;
  createdAt: string;
  content?: string;
}

/** 원장 화면: 내 진료 시간 하나와 거기 잡힌 예약 */
export interface DirectorSlot {
  slotId: number;
  startAt: string;
  visitType: VisitType;
  isEvent: boolean;
  isOpen: boolean;
  reservation: {
    reservationId: number;
    status: Status;
    petId: number;
    petName: string;
    petSpecies: Species;
    petAge: number;
    ownerName: string;
    ownerPhone: string;
    createdAt: string;
  } | null;
}

/** 원장 화면: 병원 현황 (예약 가능 기간 14일 집계) */
export interface DirectorStats {
  days: { date: string; isEvent: boolean; slots: number; closed: number; confirmed: number; requested: number; cancelled: number }[];
  byVet: { vetId: number; vetName: string; vetTitle: string; active: number; slots: number }[];
  byType: { visitType: VisitType; active: number }[];
  byWas: { servedBy: string; count: number }[];
  totals: { slots: number; active: number; confirmed: number; requested: number; cancelled: number; closed: number; open: number };
}
