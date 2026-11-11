package kr.bodeum.vet;

import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

import kr.bodeum.vet.support.ServiceBootstrap;

/** 반려동물·공지·예약 가능 시간. 슬롯 자동 생성(SlotGenerator)은 이 서비스에만 있다. */
@SpringBootApplication
@EnableScheduling
public class ClinicServiceApplication {

    public static void main(String[] args) {
        ServiceBootstrap.run(ClinicServiceApplication.class, args);
    }
}
