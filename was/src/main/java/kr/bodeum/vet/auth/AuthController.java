package kr.bodeum.vet.auth;

import java.time.Duration;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import kr.bodeum.vet.support.ApiException;

/**
 * 로그인·로그아웃·내 정보 (6장 인증 API).
 * 비밀번호는 BCrypt(강도 10) 로 검증하고, 계정별 실패 횟수를 ElastiCache 카운터로 세어 5회면 1분간 429.
 */
@RestController
@RequestMapping("/api/auth")
class AuthController {

    private static final Logger log = LoggerFactory.getLogger(AuthController.class);
    private static final int MAX_FAILS = 5;
    private static final Duration LOCK = Duration.ofMinutes(1);

    private final JdbcTemplate jdbc;
    private final StringRedisTemplate redis;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(10);

    AuthController(JdbcTemplate jdbc, StringRedisTemplate redis) {
        this.jdbc = jdbc;
        this.redis = redis;
    }

    record LoginRequest(String loginId, String password) {}
    record UserView(long userId, String loginId, String name, String role, Integer vetId) {
        static UserView of(SessionUser u) { return new UserView(u.userId(), u.loginId(), u.name(), u.role(), u.vetId()); }
    }
    private record Row(long userId, String loginId, String hash, String name, String role, Integer vetId) {}

    @PostMapping("/login")
    UserView login(@RequestBody LoginRequest req, HttpServletRequest http) {
        String loginId = req.loginId() == null ? "" : req.loginId().trim();
        String failKey = "login:fail:" + loginId;
        if (fails(failKey) >= MAX_FAILS) {
            throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "TOO_MANY_ATTEMPTS", "로그인 시도가 너무 많습니다. 잠시 후 다시 시도해 주세요.");
        }
        List<Row> rows = jdbc.query(
                "SELECT user_id, login_id, password_hash, name, role, vet_id FROM users WHERE login_id = ?",
                (rs, i) -> new Row(rs.getLong(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5),
                        (Integer) rs.getObject(6)),
                loginId);
        if (rows.isEmpty() || req.password() == null || !encoder.matches(req.password(), rows.get(0).hash())) {
            countFail(failKey);
            throw new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_CREDENTIALS", "아이디 또는 비밀번호가 올바르지 않습니다.");
        }
        clearFails(failKey);
        Row r = rows.get(0);
        SessionUser user = new SessionUser(r.userId(), r.loginId(), r.name(), r.role(), r.vetId());
        HttpSession old = http.getSession(false);
        if (old != null) old.invalidate();             // 세션 고정 공격 방지: 로그인 때 새 세션
        http.getSession(true).setAttribute(SessionUser.ATTR, user);
        return UserView.of(user);
    }

    @PostMapping("/logout")
    ResponseEntity<Void> logout(HttpServletRequest http) {
        HttpSession s = http.getSession(false);
        if (s != null) s.invalidate();                  // ElastiCache 의 세션도 지워진다
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/me")
    UserView me(HttpServletRequest http) {
        return UserView.of(Auth.user(http.getSession(false)));
    }

    // ── 시도 제한: ElastiCache 가 잠시 안 되더라도 로그인 자체는 막지 않는다 ──
    private long fails(String key) {
        try {
            String v = redis.opsForValue().get(key);
            return v == null ? 0 : Long.parseLong(v);
        } catch (RuntimeException e) {
            log.warn("시도 제한 카운터 조회 실패: {}", e.getMessage());
            return 0;
        }
    }

    private void countFail(String key) {
        try {
            Long n = redis.opsForValue().increment(key);
            if (n != null && n == 1) redis.expire(key, LOCK);
            if (n != null && n >= MAX_FAILS) redis.expire(key, LOCK);
        } catch (RuntimeException e) {
            log.warn("시도 제한 카운터 기록 실패: {}", e.getMessage());
        }
    }

    private void clearFails(String key) {
        try {
            redis.delete(key);
        } catch (RuntimeException e) {
            log.warn("시도 제한 카운터 삭제 실패: {}", e.getMessage());
        }
    }
}
