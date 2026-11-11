import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { api, messageOf } from '../../api';
import { EmrError, EmrLoading, Panel, Pill } from '../../emr/parts';
import type { Notice, NoticeCategory } from '../../types';
import { ConfirmDialog, Icon, useToast } from '../../ui';

const CATEGORIES: { key: NoticeCategory; label: string; cls: string }[] = [
  { key: 'NOTICE', label: '공지', cls: 'emr-pill-active' },
  { key: 'EVENT', label: '이벤트', cls: 'emr-pill-event' },
  { key: 'CLOSED', label: '휴진', cls: 'emr-pill-rec' },
];
const catOf = (k: NoticeCategory) => CATEGORIES.find((c) => c.key === k) ?? CATEGORIES[0];

/** 간호사 전용: 공지 등록·삭제. 소개 페이지(/notices)에 바로 반영된다. */
export default function NurseNotices() {
  const toast = useToast();
  const [list, setList] = useState<Notice[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<Notice | null>(null);
  const [category, setCategory] = useState<NoticeCategory>('NOTICE');
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const [pinned, setPinned] = useState(false);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [deleting, setDeleting] = useState<Notice | null>(null);
  const [delBusy, setDelBusy] = useState(false);

  const load = useCallback(() => {
    setError(null);
    api.notices().then(setList).catch((e) => setError(messageOf(e)));
  }, []);
  useEffect(load, [load]);

  function select(n: Notice) {
    setSelected(n);
    api.notice(n.noticeId).then(setSelected).catch(() => {});
  }
  function reset() { setTitle(''); setContent(''); setPinned(false); setCategory('NOTICE'); setFormError(null); }

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!title.trim()) return setFormError('제목을 입력하세요.');
    if (!content.trim()) return setFormError('내용을 입력하세요.');
    setBusy(true);
    setFormError(null);
    try {
      const n = await api.createNotice({ category, title: title.trim(), content: content.trim(), pinned });
      reset();
      toast('success', '공지를 등록했습니다. 소개 페이지에 바로 보입니다.');
      load();
      setSelected(n);
    } catch (err) {
      setFormError(messageOf(err));
    } finally {
      setBusy(false);
    }
  }

  async function doDelete() {
    if (!deleting) return;
    setDelBusy(true);
    try {
      await api.deleteNotice(deleting.noticeId);
      toast('success', '공지를 삭제했습니다.');
      if (selected?.noticeId === deleting.noticeId) setSelected(null);
      load();
    } catch (e) {
      toast('error', messageOf(e));
    } finally {
      setDelBusy(false);
      setDeleting(null);
    }
  }

  return (
    <div className="emr-cols emr-cols--form">
      <div className="emr-stack">
        <Panel title="공지 목록" right={<small>{list?.length ?? 0}건</small>}>
          <div className="emr-toolbar">
            <button className="emr-btn" type="button" onClick={load}><Icon name="refresh" />새로고침</button>
            <span className="emr-toolbar__spacer" />
            <a className="emr-btn" href="/notices" target="_blank" rel="noopener">소개 페이지에서 보기</a>
          </div>
          {error ? <EmrError message={error} onRetry={load} /> : !list ? <EmrLoading /> : list.length === 0 ? (
            <div className="emr-empty">등록된 공지가 없습니다.</div>
          ) : (
            <div className="emr-scroll emr-scroll--short">
              <table className="emr-table">
                <thead><tr><th className="center">No</th><th className="center">분류</th><th>제목</th><th className="center">필독</th><th>작성일</th><th className="center">삭제</th></tr></thead>
                <tbody>
                  {list.map((n, i) => {
                    const c = catOf(n.category);
                    return (
                      <tr key={n.noticeId} data-clickable className={selected?.noticeId === n.noticeId ? 'selected' : ''} tabIndex={0}
                        onClick={() => select(n)} onKeyDown={(e) => { if (e.key === 'Enter') select(n); }}>
                        <td className="center num">{list.length - i}</td>
                        <td className="center"><Pill cls={c.cls}>{c.label}</Pill></td>
                        <td style={{ whiteSpace: 'normal' }}><b>{n.title}</b></td>
                        <td className="center">{n.pinned ? '●' : ''}</td>
                        <td className="num">{n.createdAt.slice(0, 10)}</td>
                        <td className="center">
                          <button className="emr-btn" type="button" onClick={(e) => { e.stopPropagation(); setDeleting(n); }} aria-label={`${n.title} 삭제`}>삭제</button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </Panel>
        <Panel title="공지 내용" right={selected && <a href={`/notices?id=${selected.noticeId}`} target="_blank" rel="noopener" style={{ fontWeight: 500 }}>새 창으로</a>}>
          {!selected ? <div className="emr-empty">목록에서 공지를 선택하세요.</div> : (
            <div className="emr-body">
              <p style={{ fontWeight: 700, fontSize: 16 }}><Pill cls={catOf(selected.category).cls}>{catOf(selected.category).label}</Pill> {selected.title}</p>
              <p style={{ color: 'var(--emr-text-mute)', fontSize: 13, margin: '6px 0 10px' }}>{selected.createdAt.replace('T', ' ').slice(0, 16)}{selected.pinned && ' · 홈 상단 고정'}</p>
              <div style={{ whiteSpace: 'pre-line', lineHeight: 1.6, borderTop: '1px solid #e5e9f0', paddingTop: 8 }}>{selected.content ?? '불러오는 중…'}</div>
            </div>
          )}
        </Panel>
      </div>

      <Panel title="공지 작성">
        <form className="emr-body" onSubmit={submit} noValidate>
          <div className="emr-field">
            <label htmlFor="n-cat">분류</label>
            <select id="n-cat" className="emr-select" value={category} onChange={(e) => setCategory(e.target.value as NoticeCategory)}>
              {CATEGORIES.map((c) => <option key={c.key} value={c.key}>{c.label}</option>)}
            </select>
          </div>
          <div className="emr-field">
            <label htmlFor="n-title">제목</label>
            <input id="n-title" className="emr-input" value={title} onChange={(e) => setTitle(e.target.value)} maxLength={100} placeholder="예: 11월 휴진 안내" />
          </div>
          <div className="emr-field emr-field--top">
            <label htmlFor="n-content">내용</label>
            <textarea id="n-content" className="emr-textarea" rows={12} value={content} onChange={(e) => setContent(e.target.value)} placeholder="보호자님께 전할 내용을 입력하세요. 할인 공지는 예약 오픈 시각을 함께 적어 주세요." />
          </div>
          <div className="emr-field">
            <span />
            <label className="emr-check"><input type="checkbox" checked={pinned} onChange={(e) => setPinned(e.target.checked)} />홈 화면 상단에 고정 (필독)</label>
          </div>
          {formError && <EmrError message={formError} />}
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 4, marginTop: 8 }}>
            <button className="emr-btn" type="button" onClick={reset} disabled={busy}>초기화</button>
            <button className="emr-btn emr-btn-primary" type="submit" disabled={busy}>{busy ? '등록 중…' : '공지 등록'}</button>
          </div>
        </form>
      </Panel>

      <ConfirmDialog open={!!deleting} title="공지 삭제" message={deleting && <p><b>{deleting.title}</b><br />삭제하면 소개 페이지에서도 사라집니다.</p>}
        confirmLabel="삭제" danger busy={delBusy} onConfirm={doDelete} onClose={() => !delBusy && setDeleting(null)} />
    </div>
  );
}
