package kr.bodeum.vet.reservation;

import java.sql.ResultSet;
import java.sql.SQLException;

import com.fasterxml.jackson.annotation.JsonProperty;

import kr.bodeum.vet.support.Times;

/** 예약 응답 (화면 types.ts 의 Reservation 과 같은 키) */
public record ReservationView(
        long reservationId, long petId, String petName, String petSpecies, long slotId, String startAt, String visitDate,
        String visitType, int vetId, String vetName, String vetTitle, @JsonProperty("isEvent") boolean isEvent,
        String status, String servedBy, String createdAt) {

    /** SELECT 절: r.*, p.name, p.species, s.start_at, s.visit_type, s.is_event, v.* — VIEW_SQL 과 같은 순서 */
    public static final String VIEW_SQL = """
            SELECT r.reservation_id, r.pet_id, p.name, p.species, r.slot_id, s.start_at, r.visit_date, s.visit_type,
                   v.vet_id, v.name, v.title, s.is_event, r.status, r.served_by, r.created_at
              FROM reservations r
              JOIN pets p  ON p.pet_id = r.pet_id
              JOIN slots s ON s.slot_id = r.slot_id
              JOIN vets v  ON v.vet_id = s.vet_id
            """;

    public static ReservationView map(ResultSet rs, int i) throws SQLException {
        return new ReservationView(rs.getLong(1), rs.getLong(2), rs.getString(3), rs.getString(4), rs.getLong(5),
                Times.fmt(rs.getTimestamp(6)), rs.getDate(7).toLocalDate().toString(), rs.getString(8), rs.getInt(9),
                rs.getString(10), rs.getString(11), rs.getBoolean(12), rs.getString(13), rs.getString(14), Times.fmt(rs.getTimestamp(15)));
    }
}
