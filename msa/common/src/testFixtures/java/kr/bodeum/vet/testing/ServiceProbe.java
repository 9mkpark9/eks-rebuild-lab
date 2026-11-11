package kr.bodeum.vet.testing;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Set;
import java.util.TreeSet;

import org.springframework.context.ApplicationContext;
import org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerMapping;

/**
 * 서비스 테스트 도우미. DB 와 Redis 없이 띄운 서비스에 실제 HTTP 요청을 보내 확인한다.
 * 서비스가 맡은 경로 목록은 웹 서버(Apache)의 경로 분기표와 같아야 하므로 테스트로 고정한다.
 */
public final class ServiceProbe {

    private static final HttpClient HTTP = HttpClient.newHttpClient();

    private ServiceProbe() {}

    /** 이 서비스에 등록된 "/api/…" 경로. 예: "GET /api/pets", "PUT /api/pets/{id}" */
    public static Set<String> apiRoutes(ApplicationContext context) {
        var mapping = context.getBean("requestMappingHandlerMapping", RequestMappingHandlerMapping.class);
        Set<String> routes = new TreeSet<>();
        mapping.getHandlerMethods().keySet().forEach(info ->
                info.getPatternValues().stream().filter(p -> p.startsWith("/api/")).forEach(p ->
                        info.getMethodsCondition().getMethods().forEach(m -> routes.add(m + " " + p))));
        return routes;
    }

    public static HttpResponse<String> get(int port, String path) {
        try {
            return HTTP.send(HttpRequest.newBuilder(URI.create("http://localhost:" + port + path))
                    .header("Accept", "application/json").GET().build(), HttpResponse.BodyHandlers.ofString());
        } catch (IOException e) {
            throw new IllegalStateException(e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }
}
