package kr.bodeum.vet;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment;
import org.springframework.context.ApplicationContext;

import kr.bodeum.vet.testing.ServiceProbe;

/** DB 와 Redis 없이 띄운다. 연결은 요청이 올 때 맺으므로 서비스는 뜨고, 저장소가 필요한 요청만 실패한다. */
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT, properties = "spring.data.redis.host=localhost")
class ReservationServiceRoutesTest {

    @Autowired ApplicationContext context;
    @Value("${local.server.port}") int port;

    @Test
    @DisplayName("맡은 경로만 가진다 (웹 서버의 경로 분기표와 같아야 한다)")
    void ownsExactlyItsRoutes() {
        assertThat(ServiceProbe.apiRoutes(context)).containsExactlyInAnyOrder(
                "POST /api/reservations", "GET /api/reservations/me", "PUT /api/reservations/{id}", "DELETE /api/reservations/{id}",
                "GET /api/admin/reservations", "POST /api/admin/reservations/{id}/approve", "GET /api/admin/slots",
                "GET /api/director/schedule", "PUT /api/director/slots/{id}", "GET /api/director/stats");
    }

    @Test
    @DisplayName("/health 는 저장소 없이 200 이고, 응답에 처리한 서버 이름이 붙는다")
    void healthAndServedBy() {
        var res = ServiceProbe.get(port, "/health");
        assertThat(res.statusCode()).isEqualTo(200);
        assertThat(res.body()).isEqualTo("ok");
        assertThat(res.headers().firstValue("X-Served-By")).isPresent();
    }

    @Test
    @DisplayName("로그인하지 않은 요청은 401 과 { code, message } JSON")
    void unauthenticatedIs401Json() {
        var res = ServiceProbe.get(port, "/api/reservations/me");
        assertThat(res.statusCode()).isEqualTo(401);
        assertThat(res.body()).contains("\"code\":\"UNAUTHORIZED\"");
    }

    @Test
    @DisplayName("다른 서비스가 맡은 경로는 404 와 { code, message } JSON")
    void foreignRouteIs404Json() {
        var res = ServiceProbe.get(port, "/api/admin/notices");
        assertThat(res.statusCode()).isEqualTo(404);
        assertThat(res.body()).contains("\"code\":\"NOT_FOUND\"");
    }
}
