package kr.bodeum.vet.clinic;

import java.sql.PreparedStatement;
import java.sql.Statement;
import java.util.List;
import java.util.Set;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.SessionAttribute;

import kr.bodeum.vet.auth.Auth;
import kr.bodeum.vet.auth.SessionUser;
import kr.bodeum.vet.support.ApiException;

/** 보호자의 반려동물 (보호자 1 : 반려동물 N). 본인 것만 보고 바꾼다. */
@RestController
@RequestMapping("/api/pets")
class PetController {

    private static final Set<String> SPECIES = Set.of("DOG", "CAT", "ETC");
    private final JdbcTemplate jdbc;

    PetController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    record PetView(long petId, String name, String species, int age) {}
    record PetRequest(String name, String species, Integer age) {}

    @GetMapping
    List<PetView> mine(@SessionAttribute(name = SessionUser.ATTR, required = false) SessionUser me) {
        SessionUser u = Auth.require(me, Auth.OWNER);
        return jdbc.query("SELECT pet_id, name, species, age FROM pets WHERE owner_id = ? ORDER BY pet_id",
                (rs, i) -> new PetView(rs.getLong(1), rs.getString(2), rs.getString(3), rs.getInt(4)), u.userId());
    }

    @PostMapping
    ResponseEntity<PetView> create(@RequestBody PetRequest req, @SessionAttribute(name = SessionUser.ATTR, required = false) SessionUser me) {
        SessionUser u = Auth.require(me, Auth.OWNER);
        PetRequest v = validate(req);
        var key = new GeneratedKeyHolder();
        jdbc.update(con -> {
            PreparedStatement ps = con.prepareStatement("INSERT INTO pets (owner_id, name, species, age) VALUES (?, ?, ?, ?)", Statement.RETURN_GENERATED_KEYS);
            ps.setLong(1, u.userId());
            ps.setString(2, v.name());
            ps.setString(3, v.species());
            ps.setInt(4, v.age());
            return ps;
        }, key);
        return ResponseEntity.status(HttpStatus.CREATED).body(new PetView(key.getKey().longValue(), v.name(), v.species(), v.age()));
    }

    @PutMapping("/{id}")
    PetView update(@PathVariable long id, @RequestBody PetRequest req, @SessionAttribute(name = SessionUser.ATTR, required = false) SessionUser me) {
        SessionUser u = Auth.require(me, Auth.OWNER);
        PetRequest v = validate(req);
        int n = jdbc.update("UPDATE pets SET name = ?, species = ?, age = ? WHERE pet_id = ? AND owner_id = ?",
                v.name(), v.species(), v.age(), id, u.userId());
        if (n == 0) throw ApiException.notFound();
        return new PetView(id, v.name(), v.species(), v.age());
    }

    private static PetRequest validate(PetRequest r) {
        String name = r.name() == null ? "" : r.name().trim();
        if (name.isEmpty() || name.length() > 20) throw ApiException.invalid("이름은 1~20자로 입력해 주세요.");
        if (!SPECIES.contains(r.species())) throw ApiException.invalid("종류를 선택해 주세요.");
        if (r.age() == null || r.age() < 0 || r.age() > 40) throw ApiException.invalid("나이는 0~40 사이 숫자로 입력해 주세요.");
        return new PetRequest(name, r.species(), r.age());
    }
}
