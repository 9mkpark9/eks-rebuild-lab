package kr.bodeum.vet.reservation;

import java.sql.PreparedStatement;
import java.sql.Statement;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import kr.bodeum.vet.support.ApiException;
import kr.bodeum.vet.support.ServedByFilter;
import kr.bodeum.vet.support.Times;

/**
 * 중복 예약 방지 (6장, 부록 B). 판정은 DB 한 곳에서 내리므로 WAS 대수와 무관하게 결과가 같다.
 *  - 슬롯: 조건부 UPDATE (reservation_id IS NULL AND is_open = 1) → 0행이면 SLOT_TAKEN
 *  - 반려동물 1마리는 같은 날 활성 예약 1건: uq_pet_day (저장 생성 열) → PET_SAME_DAY
 *  - 실패하면 런타임 예외 → @Transactional 이 앞의 변경까지 모두 롤백
 * 격리 수준은 InnoDB 기본(REPEATABLE READ) 그대로.
 */
@Service
public class ReservationService {

    private static final String TAKE_SLOT =
            "UPDATE slots SET reservation_id = ? WHERE slot_id = ? AND reservation_id IS NULL AND is_open = 1";

    private final JdbcTemplate jdbc;

    public ReservationService(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    @Transactional
    public long create(long ownerId, long petId, long slotId) {
        requireOwnPet(ownerId, petId);
        LocalDate day = openSlotDate(slotId);
        var key = new GeneratedKeyHolder();
        try {
            jdbc.update(con -> {
                PreparedStatement ps = con.prepareStatement(
                        "INSERT INTO reservations (owner_id, pet_id, slot_id, visit_date, status, served_by, created_at) "
                                + "VALUES (?, ?, ?, ?, 'REQUESTED', ?, ?)", Statement.RETURN_GENERATED_KEYS);
                ps.setLong(1, ownerId);
                ps.setLong(2, petId);
                ps.setLong(3, slotId);
                ps.setObject(4, day);
                ps.setString(5, ServedByFilter.HOST);
                ps.setObject(6, Times.now());
                return ps;
            }, key);
        } catch (DuplicateKeyException e) {
            throw petSameDay(); // ① uq_pet_day
        }
        long rid = key.getKey().longValue();
        if (jdbc.update(TAKE_SLOT, rid, slotId) == 0) {
            throw slotTaken(); // ② 영향받은 행 0 → 이미 예약됨. INSERT 까지 롤백
        }
        return rid;
    }

    @Transactional
    public void change(long ownerId, long rid, long newSlotId) {
        Map<String, Object> r = lockMine(ownerId, rid); // 내 활성 예약 행을 FOR UPDATE 로 잠금
        long oldSlotId = ((Number) r.get("slot_id")).longValue();
        if (oldSlotId == newSlotId) return;
        LocalDate day = openSlotDate(newSlotId);
        // ① 기존 슬롯을 먼저 비운다 (uq_resv: 예약 1건은 슬롯을 하나만 가질 수 있다)
        jdbc.update("UPDATE slots SET reservation_id = NULL WHERE slot_id = ? AND reservation_id = ?", oldSlotId, rid);
        // ② 새 슬롯을 조건부로 잡는다. 실패하면 예외 → ①도 롤백되어 기존 슬롯이 남는다
        if (jdbc.update(TAKE_SLOT, rid, newSlotId) == 0) throw slotTaken();
        try {
            jdbc.update("UPDATE reservations SET slot_id = ?, visit_date = ?, status = 'REQUESTED' WHERE reservation_id = ?",
                    newSlotId, day, rid);
        } catch (DuplicateKeyException e) {
            throw petSameDay();
        }
    }

    @Transactional
    public void cancel(long ownerId, long rid) {
        Map<String, Object> r = lockMine(ownerId, rid);
        jdbc.update("UPDATE slots SET reservation_id = NULL WHERE slot_id = ? AND reservation_id = ?", r.get("slot_id"), rid);
        jdbc.update("UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = ?", rid);
    }

    @Transactional
    public void approve(long rid) {
        if (jdbc.update("UPDATE reservations SET status = 'CONFIRMED' WHERE reservation_id = ? AND status = 'REQUESTED'", rid) == 0) {
            Integer n = jdbc.queryForObject("SELECT COUNT(*) FROM reservations WHERE reservation_id = ?", Integer.class, rid);
            if (n == null || n == 0) throw ApiException.notFound();
            throw ApiException.conflict("NOT_REQUESTED", "승인 대기 상태가 아닙니다."); // 그 사이 취소됨
        }
    }

    private Map<String, Object> lockMine(long ownerId, long rid) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT slot_id, status FROM reservations WHERE reservation_id = ? AND owner_id = ? FOR UPDATE", rid, ownerId);
        if (rows.isEmpty()) throw ApiException.notFound(); // 없거나 남의 예약 — 남의 예약이 있다는 사실도 드러내지 않는다
        if ("CANCELLED".equals(rows.get(0).get("status"))) throw ApiException.conflict("CANCELLED", "이미 취소된 예약입니다.");
        return rows.get(0);
    }

    private LocalDate openSlotDate(long slotId) {
        List<LocalDate> d = jdbc.query("SELECT DATE(start_at) FROM slots WHERE slot_id = ? AND is_open = 1",
                (rs, i) -> rs.getDate(1).toLocalDate(), slotId);
        if (d.isEmpty()) throw ApiException.notFound("예약할 수 없는 시간입니다.");
        return d.get(0);
    }

    private void requireOwnPet(long ownerId, long petId) {
        Integer n = jdbc.queryForObject("SELECT COUNT(*) FROM pets WHERE pet_id = ? AND owner_id = ?", Integer.class, petId, ownerId);
        if (n == null || n == 0) throw ApiException.notFound("반려동물 정보를 찾을 수 없습니다.");
    }

    private static ApiException slotTaken() { return ApiException.conflict("SLOT_TAKEN", "이미 예약된 시간입니다."); }
    private static ApiException petSameDay() { return ApiException.conflict("PET_SAME_DAY", "같은 반려동물은 같은 날 한 건만 예약할 수 있습니다."); }
}
