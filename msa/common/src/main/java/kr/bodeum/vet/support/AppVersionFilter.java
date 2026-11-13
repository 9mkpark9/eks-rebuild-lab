package kr.bodeum.vet.support;

import java.io.IOException;

import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * 모든 응답에 이 서비스의 버전을 넣는다. X-Served-By(어느 Pod 인가)와 짝을 이룬다.
 * 화면 하단의 서버 표시가 이 값을 읽는다. 헤더를 더할 뿐 응답 본문은 바꾸지 않는다.
 */
@Component
public class AppVersionFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        res.setHeader("X-App-Version", AppVersion.VALUE);
        chain.doFilter(req, res);
    }
}
