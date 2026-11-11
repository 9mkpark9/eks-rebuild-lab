package kr.bodeum.vet.staff;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.SessionAttribute;

import com.fasterxml.jackson.annotation.JsonProperty;

import kr.bodeum.vet.auth.Auth;
import kr.bodeum.vet.auth.SessionUser;
import kr.bodeum.vet.support.ApiException;
import kr.bodeum.vet.support.Times;

/** 원장 전용 (진료실): 내 진료 일정, 내 진료 시간 열기·닫기, 병원 현황. 계정마다 vet_id 가 연결되어 있다. */
@RestController
@RequestMapping("/api/director")
class DirectorController {

    private static final String ACTIVE = "('REQUESTED','CONFIRMED')";
    private final JdbcTemplate jdbc;

    DirectorController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    record Booked(long reservationId, String status, long petId, String petName, String petSpecies, int petAge,
                  String ownerName, String ownerPhone, String createdAt) {}
    record MySlot(long slotId, String startAt, String visitType, @JsonProperty("isEvent") boolean isEvent,
                  @JsonProperty("isOpen") boolean isOpen, Booked reservation) {}
    record OpenRequest(Boolean isOpen) {}

    @GetMapping("/schedule")
    List<MySlot> schedule(@RequestParam String date, @SessionAttribute(name = SessionUser.ATTR, required = false) SessionUser me) {
        SessionUser u = Auth.require(me, Auth.DIRECTOR);
        LocalDate d = Times.parseDate(date);
        return jdbc.query("""
                SELECT s.slot_id, s.start_at, s.visit_type, s.is_event, s.is_open,
                       r.reservation_id, r.status, p.pet_id, p.name, p.species, p.age, o.name, o.phone, r.created_at
                  FROM slots s
                  LEFT JOIN reservations r ON r.reservation_id = s.reservation_id
                  LEFT JOIN pets p ON p.pet_id = r.pet_id
                  LEFT JOIN users o ON o.user_id = r.owner_id
                 WHERE s.vet_id = ? AND s.start_at >= ? AND s.start_at < ?
                 ORDER BY s.start_at
                """, (rs, i) -> {
                    Booked b = rs.getObject(6) == null ? null : new Booked(rs.getLong(6), rs.getString(7), rs.getLong(8), rs.getString(9),
                            rs.getString(10), rs.getInt(11), rs.getString(12), rs.getString(13), Times.fmt(rs.getTimestamp(14)));
                    return new MySlot(rs.getLong(1), Times.fmt(rs.getTimestamp(2)), rs.getString(3), rs.getBoolean(4), rs.getBoolean(5), b);
                }, u.vetId(), d.atStartOfDay(), d.plusDays(1).atStartOfDay());
    }

    /** 닫아도 이미 잡힌 예약은 그대로 둔다 (새 예약만 막는다). 남의 슬롯이면 403. */
    @PutMapping("/slots/{id}")
    Map<String, Object> setOpen(@PathVariable long id, @RequestBody OpenRequest req, @SessionAttribute(name = SessionUser.ATTR, required = false) SessionUser me) {
        SessionUser u = Auth.require(me, Auth.DIRECTOR);
        if (req.isOpen() == null) throw ApiException.invalid("isOpen 값이 필요합니다.");
        List<Integer> owner = jdbc.queryForList("SELECT vet_id FROM slots WHERE slot_id = ?", Integer.class, id);
        if (owner.isEmpty()) throw ApiException.notFound();
        if (!owner.get(0).equals(u.vetId())) throw ApiException.forbidden("본인 진료 시간만 바꿀 수 있습니다.");
        jdbc.update("UPDATE slots SET is_open = ? WHERE slot_id = ?", req.isOpen(), id);
        return Map.of("slotId", id, "isOpen", req.isOpen());
    }

    /** 예약 가능 기간(오늘부터 14일) 집계 */
    @GetMapping("/stats")
    Map<String, Object> stats(@SessionAttribute(name = SessionUser.ATTR, required = false) SessionUser me) {
        Auth.require(me, Auth.DIRECTOR);
        LocalDate from = LocalDate.now();
        LocalDate to = from.plusDays(14);
        Object[] win = { from.atStartOfDay(), to.atStartOfDay() };

        Map<String, Map<String, Object>> days = new LinkedHashMap<>();
        jdbc.query("""
                SELECT DATE(start_at) d, COUNT(*) n, SUM(is_open = 0) closed, MAX(is_event) ev
                  FROM slots WHERE start_at >= ? AND start_at < ? GROUP BY DATE(start_at) ORDER BY d
                """, rs -> {
                    Map<String, Object> m = new LinkedHashMap<>();
                    String d = rs.getDate(1).toLocalDate().toString();
                    m.put("date", d);
                    m.put("isEvent", rs.getBoolean(4));
                    m.put("slots", rs.getInt(2));
                    m.put("closed", rs.getInt(3));
                    m.put("confirmed", 0);
                    m.put("requested", 0);
                    m.put("cancelled", 0);
                    days.put(d, m);
                }, win);
        jdbc.query("SELECT visit_date, status, COUNT(*) FROM reservations WHERE visit_date >= ? AND visit_date < ? GROUP BY visit_date, status",
                rs -> {
                    Map<String, Object> m = days.get(rs.getDate(1).toLocalDate().toString());
                    if (m != null) m.put(rs.getString(2).toLowerCase(), rs.getInt(3));
                }, from, to);

        List<Map<String, Object>> byVet = jdbc.query("""
                SELECT v.vet_id, v.name, v.title,
                       (SELECT COUNT(*) FROM reservations r JOIN slots s ON s.slot_id = r.slot_id
                         WHERE s.vet_id = v.vet_id AND r.status IN %s AND s.start_at >= ? AND s.start_at < ?) active,
                       (SELECT COUNT(*) FROM slots s WHERE s.vet_id = v.vet_id AND s.start_at >= ? AND s.start_at < ?) slots
                  FROM vets v ORDER BY v.vet_id
                """.formatted(ACTIVE), (rs, i) -> {
                    Map<String, Object> m = new LinkedHashMap<>();
                    m.put("vetId", rs.getInt(1));
                    m.put("vetName", rs.getString(2));
                    m.put("vetTitle", rs.getString(3));
                    m.put("active", rs.getInt(4));
                    m.put("slots", rs.getInt(5));
                    return m;
                }, win[0], win[1], win[0], win[1]);

        Map<String, Integer> typeCount = new LinkedHashMap<>(Map.of("GENERAL", 0, "VACCINE", 0, "CHECKUP", 0));
        jdbc.query("""
                SELECT s.visit_type, COUNT(*) FROM reservations r JOIN slots s ON s.slot_id = r.slot_id
                 WHERE r.status IN %s AND s.start_at >= ? AND s.start_at < ? GROUP BY s.visit_type
                """.formatted(ACTIVE), rs -> { typeCount.put(rs.getString(1), rs.getInt(2)); }, win);
        List<Map<String, Object>> byType = new ArrayList<>();
        for (String t : List.of("GENERAL", "VACCINE", "CHECKUP")) byType.add(Map.of("visitType", t, "active", typeCount.get(t)));

        // 시드로 넣은 예약(served_by = 'seed')은 빼고, 실제 WAS 가 처리한 예약만 센다
        List<Map<String, Object>> byWas = jdbc.query("SELECT served_by, COUNT(*) FROM reservations WHERE served_by <> 'seed' GROUP BY served_by ORDER BY served_by",
                (rs, i) -> Map.<String, Object>of("servedBy", rs.getString(1), "count", rs.getInt(2)));

        Map<String, Object> totals = jdbc.queryForMap("""
                SELECT (SELECT COUNT(*) FROM slots WHERE start_at >= ? AND start_at < ?) AS slots,
                       (SELECT COUNT(*) FROM reservations WHERE status IN %1$s AND visit_date >= ? AND visit_date < ?) AS active,
                       (SELECT COUNT(*) FROM reservations WHERE status = 'CONFIRMED' AND visit_date >= ? AND visit_date < ?) AS confirmed,
                       (SELECT COUNT(*) FROM reservations WHERE status = 'REQUESTED' AND visit_date >= ? AND visit_date < ?) AS requested,
                       (SELECT COUNT(*) FROM reservations WHERE status = 'CANCELLED' AND visit_date >= ? AND visit_date < ?) AS cancelled,
                       (SELECT COUNT(*) FROM slots WHERE is_open = 0 AND start_at >= ? AND start_at < ?) AS closed,
                       (SELECT COUNT(*) FROM slots WHERE is_open = 1 AND reservation_id IS NULL AND start_at > ? AND start_at < ?) AS open
                """.formatted(ACTIVE),
                win[0], win[1], from, to, from, to, from, to, from, to, win[0], win[1], Times.now(), win[1]);
        Map<String, Object> t = new LinkedHashMap<>();
        totals.forEach((k, v) -> t.put(k, ((Number) v).intValue()));

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("days", new ArrayList<>(days.values()));
        out.put("byVet", byVet);
        out.put("byType", byType);
        out.put("byWas", byWas);
        out.put("totals", t);
        return out;
    }
}
