-- 서비스별 스키마로 나누기
-- 스키마와 시드는 먼저 임시 스키마 vet_load 에 넣는다 (db/schema.sql, db/gen-seed.mjs 를 고치지 않기 위해서다).
-- 여기서 테이블을 주인 서비스의 스키마로 옮기고, 남의 데이터를 읽는 창구(뷰)를 만든다.
--
--   vet_auth         users
--   vet_clinic       pets, notices, vets, slots
--   vet_reservation  reservations  +  뷰: pets, vets, users, slots
--
-- 같은 MySQL 안이라 스키마가 달라도 한 트랜잭션으로 묶인다. 중복 예약 방지(예약 INSERT + 슬롯 UPDATE)가 그대로 동작한다.

RENAME TABLE vet_load.users        TO vet_auth.users,
             vet_load.vets         TO vet_clinic.vets,
             vet_load.pets         TO vet_clinic.pets,
             vet_load.notices      TO vet_clinic.notices,
             vet_load.slots        TO vet_clinic.slots,
             vet_load.reservations TO vet_reservation.reservations;

DROP DATABASE vet_load;

-- reservation 이 남의 데이터에서 볼 수 있는 것. 뷰 이름을 원래 테이블 이름과 같게 두어 서비스의 SQL 은 고치지 않는다.
-- SQL SECURITY DEFINER: 서비스 계정은 뷰에 대한 권한만 있으면 되고, 원본 테이블에는 권한이 없다.

-- 예약 화면에 보일 반려동물 정보, 그리고 "내 반려동물인가" 확인
CREATE SQL SECURITY DEFINER VIEW vet_reservation.pets AS
  SELECT pet_id, owner_id, name, species, age FROM vet_clinic.pets;

-- 담당 수의사 이름과 직함
CREATE SQL SECURITY DEFINER VIEW vet_reservation.vets AS
  SELECT vet_id, name, title FROM vet_clinic.vets;

-- 직원 화면에 보일 보호자 이름·아이디·전화번호. 비밀번호 해시, 역할, 담당 수의사는 내주지 않는다.
CREATE SQL SECURITY DEFINER VIEW vet_reservation.users AS
  SELECT user_id, login_id, name, phone FROM vet_auth.users;

-- 진료 시간표. 읽기는 전부, 고치기는 grants.sql 에서 두 열(reservation_id, is_open)만 허락한다.
CREATE SQL SECURITY DEFINER VIEW vet_reservation.slots AS
  SELECT slot_id, vet_id, start_at, visit_type, is_event, is_open, reservation_id FROM vet_clinic.slots;
