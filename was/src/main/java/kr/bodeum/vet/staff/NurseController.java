package kr.bodeum.vet.staff;

import java.time.LocalDate;
import java.util.List;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.SessionAttribute;

import com.fasterxml.jackson.annotation.JsonProperty;

import kr.bodeum.vet.auth.Auth;
import kr.bodeum.vet.auth.SessionUser;
import kr.bodeum.vet.reservation.DeadlockRetry;
import kr.bodeum.vet.reservation.ReservationService;
import kr.bodeum.vet.reservation.ReservationView;
import kr.bodeum.vet.support.ApiException;
import kr.bodeum.vet.support.Times;

/**
 * 간호사 전용 (접수 데스크): 날짜별 전체 예약 현황, 승인, 슬롯 조회.
 * 경로는 문서 6장의 관리자 API 그대로라 부록 A Locust 의 AdminUser(admin1·admin2) 가 바뀌지 않는다.
 */
@RestController
@RequestMapping("/api/admin")
class NurseController {

    private final JdbcTemplate jdbc;
    private final ReservationService service;
    private final DeadlockRetry retry;

    NurseController(JdbcTemplate jdbc, ReservationService service, DeadlockRetry retry) {
        this.jdbc = jdbc;
        this.service = service;
        this.retry = retry;
    }

    record AdminReservationView(
            long reservationId, long petId, String petName, String petSpecies, long slotId, String startAt, String visitDate,
            String visitType, int vetId, String vetName, String vetTitle, @JsonProperty("isEvent") boolean isEvent,
            String status, String servedBy, String createdAt, String ownerName, String ownerLoginId, String ownerPhone) {}

    record AdminSlotView(long slotId, int vetId, String vetName, String vetTitle, String startAt, String visitType,
                         @JsonProperty("isEvent") boolean isEvent, @JsonProperty("isOpen") boolean isOpen,
                         Long reservationId, String petName, String status) {}

    @GetMapping("/reservations")
    List<AdminReservationView> reservations(@RequestParam String date, @SessionAttribute(name = SessionUser.ATTR, required = false) SessionUser me) {
        Auth.require(me, Auth.NURSE);
        LocalDate d = Times.parseDate(date);
        String sql = ReservationView.VIEW_SQL.replace("FROM reservations r", ", u.name, u.login_id, u.phone FROM reservations r JOIN users u ON u.user_id = r.owner_id")
                + " WHERE r.visit_date = ? ORDER BY s.start_at, v.vet_id";
        return jdbc.query(sql, (rs, i) -> {
            ReservationView r = ReservationView.map(rs, i);
            return new AdminReservationView(r.reservationId(), r.petId(), r.petName(), r.petSpecies(), r.slotId(), r.startAt(),
                    r.visitDate(), r.visitType(), r.vetId(), r.vetName(), r.vetTitle(), r.isEvent(), r.status(), r.servedBy(),
                    r.createdAt(), rs.getString(16), rs.getString(17), rs.getString(18));
        }, d);
    }

    @PostMapping("/reservations/{id}/approve")
    ReservationView approve(@PathVariable long id, @SessionAttribute(name = SessionUser.ATTR, required = false) SessionUser me) {
        Auth.require(me, Auth.NURSE);
        retry.run(() -> service.approve(id));
        return jdbc.query(ReservationView.VIEW_SQL + " WHERE r.reservation_id = ?", ReservationView::map, id)
                .stream().findFirst().orElseThrow(ApiException::notFound);
    }

    /** 남은 시간을 보고 전화 예약을 안내하는 용도. 열기·닫기는 원장 화면에서 한다. */
    @GetMapping("/slots")
    List<AdminSlotView> slots(@RequestParam String date, @SessionAttribute(name = SessionUser.ATTR, required = false) SessionUser me) {
        Auth.require(me, Auth.NURSE);
        LocalDate d = Times.parseDate(date);
        return jdbc.query("""
                SELECT s.slot_id, s.vet_id, v.name, v.title, s.start_at, s.visit_type, s.is_event, s.is_open,
                       s.reservation_id, p.name, r.status
                  FROM slots s
                  JOIN vets v ON v.vet_id = s.vet_id
                  LEFT JOIN reservations r ON r.reservation_id = s.reservation_id
                  LEFT JOIN pets p ON p.pet_id = r.pet_id
                 WHERE s.start_at >= ? AND s.start_at < ?
                 ORDER BY s.start_at, s.vet_id
                """,
                (rs, i) -> new AdminSlotView(rs.getLong(1), rs.getInt(2), rs.getString(3), rs.getString(4), Times.fmt(rs.getTimestamp(5)),
                        rs.getString(6), rs.getBoolean(7), rs.getBoolean(8), (Long) rs.getObject(9, Long.class), rs.getString(10), rs.getString(11)),
                d.atStartOfDay(), d.plusDays(1).atStartOfDay());
    }
}
