package kr.bodeum.vet.auth;

import java.io.Serializable;

/**
 * 세션에 담는 로그인 사용자. 세션은 ElastiCache(Spring Session)에 저장되므로 직렬화 가능해야 하고,
 * 어느 WAS가 요청을 받아도 같은 사용자로 보인다 (ALB 고정 세션 끔, 6장).
 */
public record SessionUser(long userId, String loginId, String name, String role, Integer vetId) implements Serializable {

    public static final String ATTR = "vet.user";

    public boolean is(String r) { return role.equals(r); }
}
