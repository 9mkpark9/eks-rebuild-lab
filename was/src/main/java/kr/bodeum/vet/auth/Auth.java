package kr.bodeum.vet.auth;

import jakarta.servlet.http.HttpSession;
import kr.bodeum.vet.support.ApiException;

/**
 * 역할 확인. 보호자(OWNER) · 간호사(NURSE, /api/admin) · 원장(DIRECTOR, /api/director)은 서로의 API를 쓸 수 없다.
 * 컨트롤러는 {@code @SessionAttribute(name = SessionUser.ATTR, required = false) SessionUser me} 로 받는다 —
 * HttpSession 을 인자로 받으면 로그인하지 않은 요청에도 세션이 새로 만들어져 ElastiCache 에 쌓이기 때문.
 */
public final class Auth {

    public static final String OWNER = "OWNER";
    public static final String NURSE = "NURSE";
    public static final String DIRECTOR = "DIRECTOR";

    private Auth() {}

    public static SessionUser user(SessionUser me) {
        if (me == null) throw ApiException.unauthorized();
        return me;
    }

    public static SessionUser user(HttpSession session) {
        return user(session == null ? null : (SessionUser) session.getAttribute(SessionUser.ATTR));
    }

    public static SessionUser require(SessionUser me, String role) {
        SessionUser u = user(me);
        if (!u.is(role)) throw ApiException.forbidden();
        return u;
    }
}
