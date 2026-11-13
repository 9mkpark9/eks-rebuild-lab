package kr.bodeum.vet.support;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 상태 쪽지(/status 화면)가 읽는 응답: 어느 서비스의 어느 버전이, 어느 Pod 에서 답했는가.
 * 경로는 서비스마다 다르다 (/api/status/auth, /api/status/clinic, /api/status/reservation).
 * 웹 서버가 이 경로를 해당 서비스로만 보내므로, 한 서비스가 멈추면 그 줄만 응답이 없다.
 *
 * /health 와 같은 이유로 DB 와 Redis 를 확인하지 않는다: 이 응답은 "프로세스가 떠서 요청을 받는다"만 뜻한다.
 * 로그인 없이 볼 수 있다. 드러나는 것은 버전과 Pod 이름뿐이다.
 */
@RestController
class StatusController {

    record Status(String service, String status, String version, String servedBy) {}

    private final String service;

    /** vet.service 는 각 서비스의 application.yml 에 있다 (auth, clinic, reservation). 없으면 시작하지 못한다. */
    StatusController(@Value("${vet.service}") String service) {
        this.service = service;
    }

    @GetMapping("/api/status/${vet.service}")
    Status status() {
        return new Status(service, "ok", AppVersion.VALUE, ServedByFilter.HOST);
    }
}
