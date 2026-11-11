package kr.bodeum.vet.support;

import java.util.TimeZone;

import org.springframework.boot.SpringApplication;

/**
 * 세 서비스가 똑같이 시작하도록 was/ 의 VetApiApplication.main 에 있던 준비 작업을 한 곳에 둔다.
 * 서비스마다 시간대가 다르면 같은 DATETIME 을 서로 다른 시각으로 읽게 된다.
 */
public final class ServiceBootstrap {

    private ServiceBootstrap() {}

    public static void run(Class<?> application, String[] args) {
        // 슬롯·예약 시각은 병원 현지 시각(DATETIME)으로 다룬다. 컨테이너 기본 시간대(UTC)와 무관하게 맞춘다.
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Seoul"));
        // DB 주소가 바뀌어도 60초 안에 따라가게 한다 (JVM DNS 캐시 60초 이하)
        java.security.Security.setProperty("networkaddress.cache.ttl", "60");
        SpringApplication.run(application, args);
    }
}
