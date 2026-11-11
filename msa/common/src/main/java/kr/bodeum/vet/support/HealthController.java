package kr.bodeum.vet.support;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * ALB 헬스 체크용. 일부러 DB를 확인하지 않는다:
 * DB 장애 때 모든 WAS가 비정상이 되면 ASG가 멀쩡한 인스턴스까지 교체하고, ALB는 fail open이 되기 때문 (부록 B).
 */
@RestController
class HealthController {

    @GetMapping("/health")
    String health() {
        return "ok";
    }
}
