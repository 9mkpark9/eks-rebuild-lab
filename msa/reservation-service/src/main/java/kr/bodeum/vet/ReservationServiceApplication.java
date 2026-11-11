package kr.bodeum.vet;

import org.springframework.boot.autoconfigure.SpringBootApplication;

import kr.bodeum.vet.support.ServiceBootstrap;

/** 보호자 예약과 직원 화면 (/api/reservations, 공지를 뺀 /api/admin, /api/director) */
@SpringBootApplication
public class ReservationServiceApplication {

    public static void main(String[] args) {
        ServiceBootstrap.run(ReservationServiceApplication.class, args);
    }
}
