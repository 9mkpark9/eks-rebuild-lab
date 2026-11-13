-- 서비스 계정별 권한. 이 파일이 "어느 서비스가 어느 데이터를 읽고 쓰는가"의 전부다.
-- 계정은 vet-provision 이 비밀번호와 함께 먼저 만든다. 여기에는 비밀번호가 없다.
-- 원본(db/init.sh)의 원칙을 따른다: SELECT·INSERT·UPDATE 만 주고, DELETE 는 공지에만 준다.

-- auth: 로그인할 때 사용자를 읽기만 한다
GRANT SELECT                 ON vet_auth.users     TO 'vet_auth'@'%';

-- clinic: 반려동물과 공지의 주인. 진료 시간표는 줄을 추가만 한다(슬롯 자동 생성)
GRANT SELECT, INSERT, UPDATE ON vet_clinic.pets    TO 'vet_clinic'@'%';
GRANT SELECT, INSERT, DELETE ON vet_clinic.notices TO 'vet_clinic'@'%';
GRANT SELECT                 ON vet_clinic.vets    TO 'vet_clinic'@'%';
GRANT SELECT, INSERT         ON vet_clinic.slots   TO 'vet_clinic'@'%';

-- reservation: 예약의 주인. 남의 데이터는 뷰로 읽기만 한다
GRANT SELECT, INSERT, UPDATE ON vet_reservation.reservations TO 'vet_reservation'@'%';
GRANT SELECT                 ON vet_reservation.pets         TO 'vet_reservation'@'%';
GRANT SELECT                 ON vet_reservation.vets         TO 'vet_reservation'@'%';
GRANT SELECT                 ON vet_reservation.users        TO 'vet_reservation'@'%';
-- 진료 시간표에서 고칠 수 있는 것은 "누가 잡았나"와 "열림 여부" 두 열뿐이다. 시각을 바꾸거나 줄을 지울 수 없다.
GRANT SELECT, UPDATE (reservation_id, is_open) ON vet_reservation.slots TO 'vet_reservation'@'%';
