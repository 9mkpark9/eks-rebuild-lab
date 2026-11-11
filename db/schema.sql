-- 동물병원 예약 시스템 스키마 (MySQL 8.4) — 6장 slots·reservations + 회원·수의사·반려동물·공지
-- 관리 EC2에서 마스터 계정으로 한 번 실행한다 (db/init.sh). 다시 실행하면 모든 데이터가 지워진다.
SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS reservations, slots, pets, notices, users, vets;
SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE vets (
  vet_id INT PRIMARY KEY,
  name   VARCHAR(20) NOT NULL,
  title  VARCHAR(20) NOT NULL,          -- 대표원장 / 원장
  field  VARCHAR(60) NOT NULL
);

CREATE TABLE users (
  user_id       BIGINT AUTO_INCREMENT PRIMARY KEY,
  login_id      VARCHAR(40)  NOT NULL,
  password_hash VARCHAR(100) NOT NULL,  -- BCrypt
  name          VARCHAR(40)  NOT NULL,
  role          ENUM('OWNER','NURSE','DIRECTOR') NOT NULL,
  phone         VARCHAR(20)  NOT NULL,
  vet_id        INT NULL,               -- 원장 계정이 맡은 수의사
  UNIQUE KEY uq_login (login_id),
  CONSTRAINT fk_user_vet FOREIGN KEY (vet_id) REFERENCES vets (vet_id)
);

CREATE TABLE pets (
  pet_id   BIGINT AUTO_INCREMENT PRIMARY KEY,
  owner_id BIGINT NOT NULL,
  name     VARCHAR(20) NOT NULL,
  species  ENUM('DOG','CAT','ETC') NOT NULL,
  age      INT NOT NULL,
  KEY ix_owner (owner_id),
  CONSTRAINT fk_pet_owner FOREIGN KEY (owner_id) REFERENCES users (user_id)
);

CREATE TABLE slots (
  slot_id        BIGINT AUTO_INCREMENT PRIMARY KEY,
  vet_id         INT NOT NULL,
  start_at       DATETIME NOT NULL,
  visit_type     VARCHAR(20) NOT NULL,          -- GENERAL / VACCINE / CHECKUP
  is_event       TINYINT NOT NULL DEFAULT 0,
  is_open        TINYINT NOT NULL DEFAULT 1,
  reservation_id BIGINT NULL,
  UNIQUE KEY uq_vet_time (vet_id, start_at),    -- 같은 수의사·같은 시각의 슬롯은 하나
  UNIQUE KEY uq_resv (reservation_id),          -- 예약 1건이 슬롯 2개를 잡지 못함 (NULL은 여러 개 허용)
  KEY ix_avail (start_at, visit_type, reservation_id),
  CONSTRAINT fk_slot_vet FOREIGN KEY (vet_id) REFERENCES vets (vet_id)
);

CREATE TABLE reservations (
  reservation_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  owner_id   BIGINT NOT NULL,
  pet_id     BIGINT NOT NULL,
  slot_id    BIGINT NOT NULL,
  visit_date DATE NOT NULL,
  status     ENUM('REQUESTED','CONFIRMED','CANCELLED') NOT NULL,
  served_by  VARCHAR(64) NOT NULL,                -- 처리한 WAS 호스트 이름
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  active_pet_day VARCHAR(40) AS
    (CASE WHEN status IN ('REQUESTED','CONFIRMED') THEN CONCAT(pet_id, '|', visit_date) END) STORED,
  UNIQUE KEY uq_pet_day (active_pet_day),         -- 반려동물 1마리는 같은 날 활성 예약 1건
  KEY ix_owner (owner_id),
  KEY ix_visit (visit_date, status)
);

CREATE TABLE notices (
  notice_id  BIGINT AUTO_INCREMENT PRIMARY KEY,
  category   ENUM('NOTICE','EVENT','CLOSED') NOT NULL DEFAULT 'NOTICE',
  title      VARCHAR(100) NOT NULL,
  content    TEXT NOT NULL,
  pinned     TINYINT NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL,
  KEY ix_created (created_at)
);
