package kr.bodeum.vet.support;

import java.io.IOException;
import java.net.InetAddress;
import java.net.UnknownHostException;

import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/** 모든 응답에 처리한 WAS 이름을 넣는다 (분산 확인용, 6장). 호스트 이름 유형이 리소스 이름이라 인스턴스 ID가 들어간다. */
@Component
public class ServedByFilter extends OncePerRequestFilter {

    public static final String HOST = hostName();

    private static String hostName() {
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException e) {
            return "unknown";
        }
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        res.setHeader("X-Served-By", HOST);
        chain.doFilter(req, res);
    }
}
