package kr.bodeum.vet.reservation;

import java.util.concurrent.ThreadLocalRandom;
import java.util.function.Supplier;

import org.springframework.dao.PessimisticLockingFailureException;
import org.springframework.stereotype.Component;

import kr.bodeum.vet.support.ApiException;

/**
 * 교착 상태(1213)·잠금 대기 초과(1205) 재시도 (6장).
 * 반드시 @Transactional 메서드 바깥(프록시 밖)에서 감싼다 — 안에서 잡으면 이미 롤백으로 표시된 트랜잭션을 이어 쓰게 된다.
 * 50~150ms 무작위 대기 후 최대 2번 다시 실행하고, 그래도 실패하면 409 BUSY.
 */
@Component
public class DeadlockRetry {

    public <T> T call(Supplier<T> work) {
        for (int attempt = 1; ; attempt++) {
            try {
                return work.get();
            } catch (PessimisticLockingFailureException e) {
                if (attempt == 3) throw ApiException.conflict("BUSY", "요청이 몰려 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.");
                try {
                    Thread.sleep(ThreadLocalRandom.current().nextLong(50, 151));
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    throw e;
                }
            }
        }
    }

    public void run(Runnable work) {
        call(() -> { work.run(); return null; });
    }
}
