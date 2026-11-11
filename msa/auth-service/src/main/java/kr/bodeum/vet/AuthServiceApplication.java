package kr.bodeum.vet;

import org.springframework.boot.autoconfigure.SpringBootApplication;

import kr.bodeum.vet.support.ServiceBootstrap;

/** 로그인·로그아웃·내 정보 (/api/auth) */
@SpringBootApplication
public class AuthServiceApplication {

    public static void main(String[] args) {
        ServiceBootstrap.run(AuthServiceApplication.class, args);
    }
}
