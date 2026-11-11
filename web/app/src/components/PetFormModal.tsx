import { useEffect, useState, type FormEvent } from 'react';
import { api, messageOf } from '../api';
import type { Pet, Species } from '../types';
import { Icon, Modal, SPECIES_LABEL, Spinner } from '../ui';

export function PetFormModal({ open, pet, onClose, onSaved }: {
  open: boolean; pet: Pet | null; onClose: () => void; onSaved: (p: Pet) => void;
}) {
  const [name, setName] = useState('');
  const [species, setSpecies] = useState<Species>('DOG');
  const [age, setAge] = useState('1');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setName(pet?.name ?? '');
    setSpecies(pet?.species ?? 'DOG');
    setAge(String(pet?.age ?? 1));
    setError(null);
  }, [open, pet]);

  async function submit(e: FormEvent) {
    e.preventDefault();
    const n = name.trim();
    const a = Number(age);
    if (!n) return setError('이름을 입력해 주세요.');
    if (n.length > 20) return setError('이름은 20자 이하로 입력해 주세요.');
    if (!Number.isInteger(a) || a < 0 || a > 40) return setError('나이는 0~40 사이의 숫자로 입력해 주세요.');
    setBusy(true);
    setError(null);
    try {
      const saved = pet ? await api.updatePet(pet.petId, { name: n, species, age: a }) : await api.createPet({ name: n, species, age: a });
      onSaved(saved);
    } catch (err) {
      setError(messageOf(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open={open} title={pet ? '반려동물 정보 수정' : '반려동물 등록'} onClose={onClose} size="sm">
      <form className="form-stack" onSubmit={submit} noValidate>
        <label className="field">
          <span className="field__label">이름</span>
          <input className="input" value={name} onChange={(e) => setName(e.target.value)} maxLength={20} placeholder="예: 콩이" data-autofocus />
        </label>
        <div className="field">
          <span className="field__label">종류</span>
          <div className="segmented" role="radiogroup" aria-label="종류">
            {(Object.keys(SPECIES_LABEL) as Species[]).map((s) => (
              <button key={s} type="button" role="radio" aria-checked={species === s} className={species === s ? 'is-on' : ''} onClick={() => setSpecies(s)}>
                <Icon name={s === 'DOG' ? 'dog' : s === 'CAT' ? 'cat' : 'paw'} />{SPECIES_LABEL[s]}
              </button>
            ))}
          </div>
        </div>
        <label className="field">
          <span className="field__label">나이 (살)</span>
          <div className="stepper">
            <button type="button" onClick={() => setAge(String(Math.max(0, Number(age || 0) - 1)))} aria-label="한 살 줄이기">−</button>
            <input className="input" inputMode="numeric" value={age} onChange={(e) => setAge(e.target.value.replace(/[^0-9]/g, ''))} aria-label="나이" />
            <button type="button" onClick={() => setAge(String(Math.min(40, Number(age || 0) + 1)))} aria-label="한 살 늘리기">+</button>
          </div>
          <span className="field__hint">1살이 안 됐으면 0으로 입력하세요.</span>
        </label>
        {error && <p className="form-error" role="alert"><Icon name="alert" />{error}</p>}
        <div className="form-actions">
          <button className="btn btn--outline" type="button" onClick={onClose} disabled={busy}>취소</button>
          <button className="btn btn--primary" type="submit" disabled={busy}>{busy ? <Spinner /> : pet ? '저장하기' : '등록하기'}</button>
        </div>
      </form>
    </Modal>
  );
}
