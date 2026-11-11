package kr.bodeum.vet.clinic;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 예약 가능 기간(오늘부터 14일)의 슬롯이 늘 있도록 채운다.
 * WAS 가 여러 대여도 uq_vet_time(같은 수의사·같은 시각은 하나) 덕분에 INSERT IGNORE 가 중복 없이 끝난다.
 * 진료 시간: 09:00~18:00, 점심 13:00~14:00, 일요일 휴진, 30분 단위 (4장).
 */
@Component
class SlotGenerator {

    private static final Logger log = LoggerFactory.getLogger(SlotGenerator.class);
    private static final String[] TYPES = { "GENERAL", "VACCINE", "CHECKUP" };
    private final JdbcTemplate jdbc;

    SlotGenerator(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    @EventListener(ApplicationReadyEvent.class)
    void onStart() { fill(); }

    @Scheduled(cron = "0 5 0 * * *", zone = "Asia/Seoul")
    void daily() { fill(); }

    void fill() {
        try {
            List<Integer> vets = jdbc.queryForList("SELECT vet_id FROM vets ORDER BY vet_id", Integer.class);
            List<LocalTime> times = new ArrayList<>();
            for (LocalTime t = LocalTime.of(9, 0); t.isBefore(LocalTime.of(18, 0)); t = t.plusMinutes(30)) {
                if (!t.isBefore(LocalTime.of(13, 0)) && t.isBefore(LocalTime.of(14, 0))) continue;
                times.add(t);
            }
            int added = 0;
            LocalDate today = LocalDate.now();
            for (int d = 0; d < 14; d++) {
                LocalDate day = today.plusDays(d);
                if (day.getDayOfWeek() == DayOfWeek.SUNDAY) continue;
                for (int vi = 0; vi < vets.size(); vi++) {
                    for (int ti = 0; ti < times.size(); ti++) {
                        // 시각마다 수의사 3명이 세 진료 항목을 하나씩 맡는다 (시드와 같은 규칙)
                        added += jdbc.update("INSERT IGNORE INTO slots (vet_id, start_at, visit_type, is_event, is_open) VALUES (?, ?, ?, 0, 1)",
                                vets.get(vi), day.atTime(times.get(ti)), TYPES[(vi + ti) % TYPES.length]);
                    }
                }
            }
            if (added > 0) log.info("슬롯 {}개 추가 (오늘부터 14일)", added);
        } catch (RuntimeException e) {
            log.warn("슬롯 채우기 실패 (DB 초기화 전일 수 있음): {}", e.getMessage());
        }
    }
}
