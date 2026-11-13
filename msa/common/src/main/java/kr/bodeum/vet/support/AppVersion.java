package kr.bodeum.vet.support;

/**
 * 이 서비스의 버전. 이미지를 빌드할 때 넣은 값(= 이미지 태그)을 환경 변수 APP_VERSION 으로 받는다.
 * 배포 전후로 화면과 /status 의 값이 바뀌는 것을 보여 주기 위한 것이다.
 */
public final class AppVersion {

    /** 이미지 밖에서 jar 를 직접 실행하면 환경 변수가 없으므로 dev 로 보인다. */
    public static final String VALUE = resolve();

    private AppVersion() {}

    private static String resolve() {
        String v = System.getenv("APP_VERSION");
        return (v == null || v.isBlank()) ? "dev" : v.trim();
    }
}
