import { useCallback, useEffect, useState } from 'react';
import { api, messageOf } from '../api';
import { PetFormModal } from '../components/PetFormModal';
import { josa } from '../lib/text';
import { Link } from '../router';
import type { Pet } from '../types';
import { EmptyState, ErrorBox, Icon, PageLoading, SPECIES_LABEL, SpeciesAvatar, useToast } from '../ui';

export default function Pets() {
  const toast = useToast();
  const [pets, setPets] = useState<Pet[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Pet | null>(null);
  const [open, setOpen] = useState(false);

  const load = useCallback(() => {
    setError(null);
    api.pets().then(setPets).catch((e) => setError(messageOf(e)));
  }, []);
  useEffect(load, [load]);

  if (error) return <ErrorBox message={error} onRetry={load} />;
  if (!pets) return <PageLoading />;

  return (
    <div className="stack-lg">
      <header className="page-head page-head--row">
        <div>
          <h1 className="page-head__title">내 반려동물</h1>
          <p className="page-head__desc">진료와 예방접종은 아이별로 예약합니다. 여러 아이를 키우면 모두 등록해 주세요.</p>
        </div>
        <button className="btn btn--primary" type="button" onClick={() => { setEditing(null); setOpen(true); }}><Icon name="plus" />반려동물 등록</button>
      </header>

      {pets.length === 0 ? (
        <EmptyState icon="paw" title="등록된 반려동물이 없어요" desc="이름, 종류, 나이만 입력하면 됩니다."
          action={<button className="btn btn--primary btn--sm" type="button" onClick={() => setOpen(true)}>첫 반려동물 등록</button>} />
      ) : (
        <ul className="pet-grid">
          {pets.map((p) => (
            <li key={p.petId} className="pet-card">
              <SpeciesAvatar species={p.species} size="lg" />
              <h2 className="pet-card__name">{p.name}</h2>
              <p className="pet-card__info">{SPECIES_LABEL[p.species]} · {p.age}살</p>
              <div className="pet-card__actions">
                <button className="btn btn--sm btn--outline" type="button" onClick={() => { setEditing(p); setOpen(true); }}><Icon name="edit" />수정</button>
                <Link to={`/app/reserve?pet=${p.petId}`} className="btn btn--sm btn--primary">예약하기</Link>
              </div>
            </li>
          ))}
          <li>
            <button className="pet-card pet-card--add" type="button" onClick={() => { setEditing(null); setOpen(true); }}>
              <span className="pet-avatar pet-avatar--add pet-avatar--lg"><Icon name="plus" /></span>
              <span className="pet-card__name">반려동물 추가</span>
              <span className="pet-card__info">새 가족을 등록하세요</span>
            </button>
          </li>
        </ul>
      )}

      <PetFormModal open={open} pet={editing} onClose={() => setOpen(false)} onSaved={(saved) => {
        setPets((xs) => {
          const list = xs ?? [];
          return list.some((x) => x.petId === saved.petId) ? list.map((x) => (x.petId === saved.petId ? saved : x)) : [...list, saved];
        });
        setOpen(false);
        toast('success', editing ? `${josa(saved.name, '의', '의')} 정보를 저장했어요.` : `${josa(saved.name, '이', '가')} 등록되었어요.`);
      }} />
    </div>
  );
}
