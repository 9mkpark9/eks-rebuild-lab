package kr.bodeum.vet.support;

import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;

/** 화면과 주고받는 시각 형식: 'YYYY-MM-DDTHH:mm:ss' (병원 현지 시각), 날짜: 'YYYY-MM-DD' */
public final class Times {

    private static final DateTimeFormatter DT = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss");

    private Times() {}

    public static String fmt(LocalDateTime t) { return t == null ? null : t.format(DT); }
    public static String fmt(Timestamp t) { return t == null ? null : fmt(t.toLocalDateTime()); }
    public static LocalDateTime now() { return LocalDateTime.now().withNano(0); }

    public static LocalDate parseDate(String s) {
        if (s == null) throw ApiException.invalid("date는 YYYY-MM-DD 형식이어야 합니다.");
        try {
            return LocalDate.parse(s);
        } catch (DateTimeParseException e) {
            throw ApiException.invalid("date는 YYYY-MM-DD 형식이어야 합니다.");
        }
    }
}
