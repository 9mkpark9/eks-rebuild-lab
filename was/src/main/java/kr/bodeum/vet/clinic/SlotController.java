package kr.bodeum.vet.clinic;

import java.time.LocalDate;
import java.util.List;
import java.util.Set;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.annotation.JsonProperty;

import kr.bodeum.vet.support.ApiException;
import kr.bodeum.vet.support.Times;

/**
 * 예약 가능 시간: 비어 있고(reservation_id IS NULL), 열려 있고(is_open = 1), 지금 이후인 슬롯만.
 * Locust 가 받은 목록에서 바로 골라 신청하므로 마감된 슬롯은 돌려주지 않는다 (부록 A).
 */
@RestController
class SlotController {

    static final Set<String> TYPES = Set.of("GENERAL", "VACCINE", "CHECKUP");
    private final JdbcTemplate jdbc;

    SlotController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    record SlotView(long slotId, int vetId, String vetName, String vetTitle, String startAt, String visitType,
                    @JsonProperty("isEvent") boolean isEvent) {}

    @GetMapping("/api/slots")
    List<SlotView> available(@RequestParam String date, @RequestParam(required = false) String type) {
        LocalDate d = Times.parseDate(date);
        if (type != null && !TYPES.contains(type)) throw ApiException.invalid("알 수 없는 진료 항목입니다.");
        return jdbc.query("""
                SELECT s.slot_id, s.vet_id, v.name, v.title, s.start_at, s.visit_type, s.is_event
                  FROM slots s JOIN vets v ON v.vet_id = s.vet_id
                 WHERE s.start_at >= ? AND s.start_at < ?
                   AND (? IS NULL OR s.visit_type = ?)
                   AND s.is_open = 1 AND s.reservation_id IS NULL AND s.start_at > ?
                 ORDER BY s.start_at, s.vet_id
                """,
                (rs, i) -> new SlotView(rs.getLong(1), rs.getInt(2), rs.getString(3), rs.getString(4),
                        Times.fmt(rs.getTimestamp(5)), rs.getString(6), rs.getBoolean(7)),
                d.atStartOfDay(), d.plusDays(1).atStartOfDay(), type, type, Times.now());
    }
}
