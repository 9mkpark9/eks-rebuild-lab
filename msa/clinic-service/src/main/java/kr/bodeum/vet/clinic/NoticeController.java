package kr.bodeum.vet.clinic;

import java.sql.PreparedStatement;
import java.sql.Statement;
import java.util.List;
import java.util.Set;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.SessionAttribute;

import com.fasterxml.jackson.annotation.JsonInclude;

import kr.bodeum.vet.auth.Auth;
import kr.bodeum.vet.auth.SessionUser;
import kr.bodeum.vet.support.ApiException;
import kr.bodeum.vet.support.Times;

/** 공지: 누구나 조회(소개 페이지), 간호사만 등록·삭제. */
@RestController
class NoticeController {

    private static final Set<String> CATEGORIES = Set.of("NOTICE", "EVENT", "CLOSED");
    private final JdbcTemplate jdbc;

    NoticeController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    @JsonInclude(JsonInclude.Include.NON_NULL)
    record NoticeView(long noticeId, String category, String title, boolean pinned, String createdAt, String content) {}
    record NoticeRequest(String category, String title, String content, Boolean pinned) {}

    @GetMapping("/api/notices")
    List<NoticeView> list() {
        return jdbc.query("SELECT notice_id, category, title, pinned, created_at FROM notices ORDER BY created_at DESC, notice_id DESC",
                (rs, i) -> new NoticeView(rs.getLong(1), rs.getString(2), rs.getString(3), rs.getBoolean(4), Times.fmt(rs.getTimestamp(5)), null));
    }

    @GetMapping("/api/notices/{id}")
    NoticeView detail(@PathVariable long id) {
        return find(id).orElseThrow(() -> ApiException.notFound("공지사항을 찾을 수 없습니다."));
    }

    private java.util.Optional<NoticeView> find(long id) {
        return jdbc.query("SELECT notice_id, category, title, pinned, created_at, content FROM notices WHERE notice_id = ?",
                (rs, i) -> new NoticeView(rs.getLong(1), rs.getString(2), rs.getString(3), rs.getBoolean(4), Times.fmt(rs.getTimestamp(5)), rs.getString(6)),
                id).stream().findFirst();
    }

    @PostMapping("/api/admin/notices")
    ResponseEntity<NoticeView> create(@RequestBody NoticeRequest req, @SessionAttribute(name = SessionUser.ATTR, required = false) SessionUser me) {
        Auth.require(me, Auth.NURSE);
        String title = req.title() == null ? "" : req.title().trim();
        String content = req.content() == null ? "" : req.content().trim();
        if (title.isEmpty() || title.length() > 100) throw ApiException.invalid("제목은 1~100자로 입력해 주세요.");
        if (content.isEmpty()) throw ApiException.invalid("내용을 입력해 주세요.");
        String category = CATEGORIES.contains(req.category()) ? req.category() : "NOTICE";
        var key = new GeneratedKeyHolder();
        jdbc.update(con -> {
            PreparedStatement ps = con.prepareStatement(
                    "INSERT INTO notices (category, title, content, pinned, created_at) VALUES (?, ?, ?, ?, ?)", Statement.RETURN_GENERATED_KEYS);
            ps.setString(1, category);
            ps.setString(2, title);
            ps.setString(3, content);
            ps.setBoolean(4, Boolean.TRUE.equals(req.pinned()));
            ps.setObject(5, Times.now());
            return ps;
        }, key);
        return ResponseEntity.status(HttpStatus.CREATED).body(find(key.getKey().longValue()).orElseThrow());
    }

    @DeleteMapping("/api/admin/notices/{id}")
    ResponseEntity<Void> delete(@PathVariable long id, @SessionAttribute(name = SessionUser.ATTR, required = false) SessionUser me) {
        Auth.require(me, Auth.NURSE);
        if (jdbc.update("DELETE FROM notices WHERE notice_id = ?", id) == 0) throw ApiException.notFound();
        return ResponseEntity.noContent().build();
    }
}
