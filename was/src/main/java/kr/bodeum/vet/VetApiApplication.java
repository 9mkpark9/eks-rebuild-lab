package kr.bodeum.vet;

import java.util.TimeZone;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class VetApiApplication {

    public static void main(String[] args) {
        // 슬롯·예약 시각은 병원 현지 시각(DATETIME)으로 다룬다. EC2 기본 시간대(UTC)와 무관하게 맞춘다.
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Seoul"));
        // RDS 장애 조치 후 바뀐 주소를 60초 안에 따라가게 한다 (AWS 권장: JVM DNS TTL 60초 이하, 11장)
        java.security.Security.setProperty("networkaddress.cache.ttl", "60");
        SpringApplication.run(VetApiApplication.class, args);
    }
}
