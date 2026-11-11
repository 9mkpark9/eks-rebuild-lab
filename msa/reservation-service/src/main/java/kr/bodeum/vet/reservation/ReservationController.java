package kr.bodeum.vet.reservation;

import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.SessionAttribute;

import kr.bodeum.vet.auth.Auth;
import kr.bodeum.vet.auth.SessionUser;
import kr.bodeum.vet.support.ApiException;

/** 보호자 예약: 신청·변경·취소·내 예약 (6장 API 표) */
@RestController
@RequestMapping("/api/reservations")
class ReservationController {

    private final ReservationService service;
    private final DeadlockRetry retry;
    private final JdbcTemplate jdbc;

    ReservationController(ReservationService service, DeadlockRetry retry, JdbcTemplate jdbc) {
        this.service = service;
        this.retry = retry;
        this.jdbc = jdbc;
    }

    record CreateRequest(Long petId, Long slotId) {}
    record ChangeRequest(Long slotId) {}

    @PostMapping
    ResponseEntity<ReservationView> create(@RequestBody CreateRequest req, @SessionAttribute(name = SessionUser.ATTR, required = false) SessionUser me) {
        SessionUser u = Auth.require(me, Auth.OWNER);
        if (req.petId() == null || req.slotId() == null) throw ApiException.invalid("petId 와 slotId 가 필요합니다.");
        long rid = retry.call(() -> service.create(u.userId(), req.petId(), req.slotId()));
        return ResponseEntity.status(HttpStatus.CREATED).body(view(rid));
    }

    @GetMapping("/me")
    List<ReservationView> mine(@SessionAttribute(name = SessionUser.ATTR, required = false) SessionUser me) {
        SessionUser u = Auth.require(me, Auth.OWNER);
        return jdbc.query(ReservationView.VIEW_SQL + " WHERE r.owner_id = ? ORDER BY s.start_at", ReservationView::map, u.userId());
    }

    @PutMapping("/{id}")
    ReservationView change(@PathVariable long id, @RequestBody ChangeRequest req, @SessionAttribute(name = SessionUser.ATTR, required = false) SessionUser me) {
        SessionUser u = Auth.require(me, Auth.OWNER);
        if (req.slotId() == null) throw ApiException.invalid("slotId 가 필요합니다.");
        retry.run(() -> service.change(u.userId(), id, req.slotId()));
        return view(id);
    }

    @DeleteMapping("/{id}")
    ResponseEntity<Void> cancel(@PathVariable long id, @SessionAttribute(name = SessionUser.ATTR, required = false) SessionUser me) {
        SessionUser u = Auth.require(me, Auth.OWNER);
        retry.run(() -> service.cancel(u.userId(), id));
        return ResponseEntity.noContent().build();
    }

    private ReservationView view(long rid) {
        return jdbc.query(ReservationView.VIEW_SQL + " WHERE r.reservation_id = ?", ReservationView::map, rid)
                .stream().findFirst().orElseThrow(ApiException::notFound);
    }
}
