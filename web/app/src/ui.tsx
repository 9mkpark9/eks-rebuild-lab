import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react';
import clinic from '../../clinic.config.json';
import type { Species, Status, VisitType } from './types';

/* ---------- 아이콘 (소개 페이지와 같은 스프라이트) ---------- */
export function Icon({ name, className = '', label }: { name: string; className?: string; label?: string }) {
  return (
    <svg className={`icon ${className}`} aria-hidden={label ? undefined : true} role={label ? 'img' : undefined} aria-label={label}>
      <use href={`/assets/img/icons.svg#${name}`} />
    </svg>
  );
}

export const SPECIES_LABEL: Record<Species, string> = { DOG: '강아지', CAT: '고양이', ETC: '기타' };
const SPECIES_ICON: Record<Species, string> = { DOG: 'dog', CAT: 'cat', ETC: 'paw' };
export function SpeciesAvatar({ species, size = 'md' }: { species: Species; size?: 'sm' | 'md' | 'lg' }) {
  return (
    <span className={`pet-avatar pet-avatar--${species.toLowerCase()} pet-avatar--${size}`}>
      <Icon name={SPECIES_ICON[species]} />
    </span>
  );
}

export const TYPE_INFO: Record<VisitType, { name: string; desc: string; icon: string; tone: string; short: string }> = {
  GENERAL: { name: clinic.visitTypes[0].name, desc: clinic.visitTypes[0].desc, icon: 'stethoscope', tone: 'primary', short: '일반' },
  VACCINE: { name: clinic.visitTypes[1].name, desc: clinic.visitTypes[1].desc, icon: 'syringe', tone: 'accent', short: '접종' },
  CHECKUP: { name: clinic.visitTypes[2].name, desc: clinic.visitTypes[2].desc, icon: 'clipboard', tone: 'info', short: '검진' },
};
export function TypeBadge({ type }: { type: VisitType }) {
  const t = TYPE_INFO[type];
  return <span className={`badge badge--${t.tone} badge--type`}>{t.name}</span>;
}

const STATUS_INFO: Record<Status, { label: string; cls: string }> = {
  REQUESTED: { label: '승인 대기', cls: 'badge--warn' },
  CONFIRMED: { label: '예약 확정', cls: 'badge--primary' },
  CANCELLED: { label: '취소됨', cls: '' },
};
export function StatusBadge({ status }: { status: Status }) {
  const s = STATUS_INFO[status];
  return <span className={`badge ${s.cls} badge--status-${status.toLowerCase()}`}>{s.label}</span>;
}

export function Spinner({ label = '불러오는 중' }: { label?: string }) {
  return <span className="spinner" role="status"><span className="sr-only">{label}</span></span>;
}

export function PageLoading() {
  return <div className="page-loading"><Spinner /></div>;
}

export function EmptyState({ icon, title, desc, action }: { icon: string; title: string; desc?: ReactNode; action?: ReactNode }) {
  return (
    <div className="empty">
      <span className="empty__icon"><Icon name={icon} /></span>
      <p className="empty__title">{title}</p>
      {desc && <p className="empty__desc">{desc}</p>}
      {action && <div className="empty__action">{action}</div>}
    </div>
  );
}

export function ErrorBox({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="notice-box notice-box--danger" role="alert">
      <Icon name="alert" />
      <span>{message}</span>
      {onRetry && <button className="btn btn--xs btn--outline" type="button" onClick={onRetry}>다시 시도</button>}
    </div>
  );
}

/* ---------- 모달 (네이티브 dialog: 포커스 가두기와 Esc 닫기를 브라우저가 처리) ---------- */
export function Modal({ open, title, onClose, children, footer, size = 'md' }: {
  open: boolean; title: string; onClose: () => void; children: ReactNode; footer?: ReactNode; size?: 'sm' | 'md' | 'lg';
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) {
      d.showModal();
      // showModal 은 첫 포커스 요소(닫기 버튼)로 포커스를 옮기므로, 입력 칸이 있으면 그쪽으로 다시 옮긴다
      d.querySelector<HTMLElement>('[data-autofocus], .modal__body input:not([type="checkbox"]), .modal__body textarea')?.focus();
    }
    if (!open && d.open) d.close();
  }, [open]);
  return (
    <dialog
      ref={ref}
      className={`modal modal--${size}`}
      onCancel={(e) => { e.preventDefault(); onClose(); }}
      onClick={(e) => { if (e.target === ref.current) onClose(); }}
      aria-labelledby="modal-title"
    >
      {open && (
        <div className="modal__inner">
          <header className="modal__head">
            <h2 id="modal-title" className="modal__title">{title}</h2>
            <button className="modal__close" type="button" onClick={onClose} aria-label="닫기"><Icon name="close" /></button>
          </header>
          <div className="modal__body">{children}</div>
          {footer && <footer className="modal__foot">{footer}</footer>}
        </div>
      )}
    </dialog>
  );
}

export function ConfirmDialog({ open, title, message, confirmLabel, danger, busy, onConfirm, onClose }: {
  open: boolean; title: string; message: ReactNode; confirmLabel: string; danger?: boolean; busy?: boolean;
  onConfirm: () => void; onClose: () => void;
}) {
  return (
    <Modal open={open} title={title} onClose={onClose} size="sm" footer={
      <>
        <button className="btn btn--outline" type="button" onClick={onClose} disabled={busy}>닫기</button>
        <button className={`btn ${danger ? 'btn--danger-solid' : 'btn--primary'}`} type="button" onClick={onConfirm} disabled={busy}>
          {busy ? <Spinner /> : confirmLabel}
        </button>
      </>
    }>
      <div className="confirm-text">{message}</div>
    </Modal>
  );
}

/* ---------- 토스트 ---------- */
type ToastKind = 'success' | 'error' | 'info';
interface Toast { id: number; kind: ToastKind; text: string }
const ToastCtx = createContext<(kind: ToastKind, text: string) => void>(() => {});
export const useToast = () => useContext(ToastCtx);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<Toast[]>([]);
  const seq = useRef(0);
  const push = useCallback((kind: ToastKind, text: string) => {
    const id = ++seq.current;
    setItems((xs) => [...xs.slice(-2), { id, kind, text }]);
    window.setTimeout(() => setItems((xs) => xs.filter((t) => t.id !== id)), kind === 'error' ? 5000 : 3200);
  }, []);
  const icon: Record<ToastKind, string> = { success: 'check-circle', error: 'alert', info: 'info' };
  return (
    <ToastCtx.Provider value={push}>
      {children}
      <div className="toasts" aria-live="polite" aria-atomic="false">
        {items.map((t) => (
          <div key={t.id} className={`toast toast--${t.kind}`} role={t.kind === 'error' ? 'alert' : 'status'}>
            <Icon name={icon[t.kind]} />
            <span>{t.text}</span>
          </div>
        ))}
      </div>
    </ToastCtx.Provider>
  );
}
