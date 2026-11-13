import type { AdminReservation, AdminSlot, DirectorSlot, DirectorStats, Notice, NoticeCategory, Pet, Reservation, Slot, Species, User, VisitType } from './types';

export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

// 409 응답 코드별 안내 문구 (6장 「변경·취소의 실패 처리」)
const FRIENDLY: Record<string, string> = {
  SLOT_TAKEN: '방금 다른 보호자님이 예약한 시간이에요. 다른 시간을 선택해 주세요.',
  PET_SAME_DAY: '이 반려동물은 그날 이미 예약이 있어요. 하루에 한 건만 예약할 수 있습니다.',
  CANCELLED: '이미 취소된 예약입니다.',
  BUSY: '예약이 몰려 처리하지 못했어요. 잠시 후 다시 시도해 주세요.',
  NOT_REQUESTED: '승인 대기 상태가 아닌 예약입니다. 그사이 보호자가 취소했을 수 있어요.',
  INVALID_CREDENTIALS: '아이디 또는 비밀번호가 올바르지 않습니다.',
  TOO_MANY_ATTEMPTS: '로그인 시도가 너무 많습니다. 1분 뒤 다시 시도해 주세요.',
  UNAUTHORIZED: '로그인이 필요합니다.',
  FORBIDDEN: '이 화면을 볼 권한이 없습니다.',
  NETWORK: '서버에 연결할 수 없습니다. 인터넷 연결을 확인하고 다시 시도해 주세요.',
};

export function messageOf(err: unknown): string {
  if (err instanceof ApiError) return FRIENDLY[err.code] ?? err.message;
  return '알 수 없는 오류가 발생했습니다.';
}

/* 분산 확인용 헤더 (X-Web-Node, X-Served-By) — 화면 하단에 마지막 처리 서버를 보여 준다.
   버전 헤더(X-Web-Version, X-App-Version)는 이미지 태그와 같은 값이라 배포 전후로 바뀐다. */
export interface NodeInfo { web: string | null; was: string | null; webVersion: string | null; wasVersion: string | null }
let lastNode: NodeInfo = { web: null, was: null, webVersion: null, wasVersion: null };
const nodeListeners = new Set<() => void>();
export const nodeStore = {
  get: () => lastNode,
  subscribe: (fn: () => void) => { nodeListeners.add(fn); return () => { nodeListeners.delete(fn); }; },
};

let onUnauthorized: (() => void) | null = null;
export function setUnauthorizedHandler(fn: (() => void) | null) { onUnauthorized = fn; }

async function request<T>(method: string, url: string, body?: unknown): Promise<T> {
  let res: Response;
  try {
    res = await fetch(url, {
      method,
      credentials: 'same-origin',
      headers: body === undefined ? { Accept: 'application/json' } : { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(0, 'NETWORK', FRIENDLY.NETWORK);
  }

  const web = res.headers.get('X-Web-Node');
  const was = res.headers.get('X-Served-By');
  if (web || was) {
    // 웹 서버가 직접 답한 응답(서비스가 멈췄을 때의 503 등)에는 서비스 쪽 헤더가 없다. 그때는 마지막 값을 둔다.
    lastNode = {
      web,
      was: was ?? lastNode.was,
      webVersion: res.headers.get('X-Web-Version') ?? lastNode.webVersion,
      wasVersion: was ? res.headers.get('X-App-Version') : lastNode.wasVersion,
    };
    nodeListeners.forEach((fn) => fn());
  }

  if (res.status === 204) return undefined as T;
  let data: unknown = null;
  try { data = await res.json(); } catch { /* 본문 없음 */ }

  if (!res.ok) {
    const d = (data ?? {}) as { code?: string; message?: string };
    const code = d.code ?? `HTTP_${res.status}`;
    const message = d.message ?? (res.status >= 500 ? '서버에 일시적인 문제가 있습니다. 잠시 후 다시 시도해 주세요.' : `요청을 처리하지 못했습니다 (${res.status}).`);
    if (res.status === 401 && onUnauthorized && !url.startsWith('/api/auth/')) onUnauthorized();
    throw new ApiError(res.status, code, message);
  }
  return data as T;
}

const q = encodeURIComponent;

export const api = {
  // 인증 — 세션은 ElastiCache에 저장된다
  me: () => request<User>('GET', '/api/auth/me'),
  login: (loginId: string, password: string) => request<User>('POST', '/api/auth/login', { loginId, password }),
  logout: () => request<void>('POST', '/api/auth/logout'),

  // 공지
  notices: () => request<Notice[]>('GET', '/api/notices'),
  notice: (id: number) => request<Notice>('GET', `/api/notices/${id}`),

  // 반려동물
  pets: () => request<Pet[]>('GET', '/api/pets'),
  createPet: (p: { name: string; species: Species; age: number }) => request<Pet>('POST', '/api/pets', p),
  updatePet: (id: number, p: { name: string; species: Species; age: number }) => request<Pet>('PUT', `/api/pets/${id}`, p),

  // 예약
  slots: (date: string, type: VisitType) => request<Slot[]>('GET', `/api/slots?date=${q(date)}&type=${q(type)}`),
  createReservation: (petId: number, slotId: number) => request<Reservation>('POST', '/api/reservations', { petId, slotId }),
  myReservations: () => request<Reservation[]>('GET', '/api/reservations/me'),
  changeReservation: (id: number, slotId: number) => request<Reservation>('PUT', `/api/reservations/${id}`, { slotId }),
  cancelReservation: (id: number) => request<void>('DELETE', `/api/reservations/${id}`),

  // 간호사 (접수 데스크) — 경로는 Locust와 맞춰 /api/admin 그대로
  adminReservations: (date: string) => request<AdminReservation[]>('GET', `/api/admin/reservations?date=${q(date)}`),
  approve: (id: number) => request<Reservation>('POST', `/api/admin/reservations/${id}/approve`),
  adminSlots: (date: string) => request<AdminSlot[]>('GET', `/api/admin/slots?date=${q(date)}`),
  createNotice: (n: { category: NoticeCategory; title: string; content: string; pinned: boolean }) => request<Notice>('POST', '/api/admin/notices', n),
  deleteNotice: (id: number) => request<void>('DELETE', `/api/admin/notices/${id}`),

  // 원장 (수의사) — 본인 진료만
  directorSchedule: (date: string) => request<DirectorSlot[]>('GET', `/api/director/schedule?date=${q(date)}`),
  setMySlotOpen: (id: number, isOpen: boolean) => request<DirectorSlot>('PUT', `/api/director/slots/${id}`, { isOpen }),
  directorStats: () => request<DirectorStats>('GET', '/api/director/stats'),
};
