"""동물병원 예약 시스템 부하 테스트 (Locust 2.x) — 문서 부록 A

실행 예 (TC-03~05 연속, Locust EC2 에서):
  cd /opt/loadtest
  PROFILE=spike WORKERS=2 locust -f locustfile.py --master --headless --expect-workers 2 \
      -H http://<외부 ALB DNS 이름> --csv results/spike --html results/spike.html
  PROFILE=spike WORKERS=2 locust -f locustfile.py --worker --master-host 127.0.0.1   # 워커마다

PROFILE: tc02 · spike(TC-03~05) · tc06 · tc08 · stress · WEB 전용: web02 · webspike · web06 · webstress(과부하 지점 찾기: 3분마다 +100명, 100→1000명)
WAIT_SCALE: 사용자 대기 시간 배율(기본 1). stress 때 0.2 등으로 줄이면 같은 사용자 수로 요청이 5배가 된다.
계정: owner001~owner300(보호자), admin1·admin2(간호사 = 문서의 관리자). 비밀번호는 테스트용 공통값.
"""
import os
import random
from collections import Counter
from datetime import date, timedelta

from locust import HttpUser, LoadTestShape, between, events, task
from locust.exception import StopUser


def _next_monday(d: date) -> date:
    """시드의 할인 기간 = 오늘 이후 첫 월요일부터 진료일 3일 (db/gen-seed.mjs 와 같은 규칙)"""
    return d + timedelta(days=(7 - d.weekday()) % 7 or 7)


PROFILE = os.getenv("PROFILE", "spike")
WORKERS = int(os.getenv("WORKERS", "1"))  # --expect-workers 와 같은 값
OWNER_ACCOUNTS = int(os.getenv("OWNER_ACCOUNTS", "300"))
PASSWORD = os.getenv("TEST_PASSWORD", "test-only")  # 가짜 테스트 계정 공통 비밀번호
EVENT_START = date.fromisoformat(os.getenv("EVENT_START", _next_monday(date.today()).isoformat()))
EVENT_DAYS = 3
TIME_SCALE = float(os.getenv("TIME_SCALE", "1"))  # 리허설 때 0.1 등으로 시간 압축
WAIT = float(os.getenv("WAIT_SCALE", "1"))         # 사용자 대기 시간 배율 (stress 에서 줄여 과부하를 만든다)
STRESS_STEP = int(os.getenv("STRESS_STEP", "100"))       # stress: 단계마다 늘릴 사용자 수
STRESS_STEPS = int(os.getenv("STRESS_STEPS", "10"))      # stress: 단계 수
STRESS_STEP_SEC = int(os.getenv("STRESS_STEP_SEC", "180"))  # stress: 단계 길이(초)

# ── 테스트 계정 배분: 워커마다 겹치지 않는 계정만 쓴다 ────────────────
_accounts = None


def take_account(env):
    global _accounts
    if _accounts is None:
        idx = max(env.runner.worker_index, 0)
        _accounts = [i for i in range(1, OWNER_ACCOUNTS + 1) if i % WORKERS == idx]
        random.shuffle(_accounts)
    return _accounts.pop() if _accounts else None


def return_account(acc):
    if acc is not None and _accounts is not None:
        _accounts.insert(0, acc)


# ── 분산 확인용 헤더 집계 (워커 → 마스터로 모은다) ───────────────────
counts = Counter()  # 이 프로세스에서 아직 보고하지 않은 값
merged = Counter()  # 마스터(또는 단독 실행)가 모은 값
lat = Counter()     # WEB 노드별 응답 시간 히스토그램 "노드|ms" (사양 비교용)
lat_merged = Counter()


def _bucket(ms):
    """1초 미만은 1ms, 그 이상은 10ms 단위로 묶어 키 수를 줄인다"""
    ms = int(ms or 0)
    return ms if ms < 1000 else ms // 10 * 10


@events.request.add_listener
def on_request(response=None, **_):
    if response is None:
        return
    web = response.headers.get("X-Web-Node")
    was = response.headers.get("X-Served-By")
    if web:
        counts["web:" + web] += 1
        lat[f"{web}|{_bucket(_.get('response_time'))}"] += 1
    if was:
        counts["was:" + was] += 1
        lat[f"was:{was}|{_bucket(_.get('response_time'))}"] += 1   # WAS 노드별 응답 시간 (코드 부하 확인)
    code = getattr(response, "status_code", 0) or 0
    if code == 409 or code == 429 or code >= 500:   # 업무 충돌(409 SLOT_TAKEN·BUSY 등)과 오류를 코드별로 센다
        reason = ""
        try:
            reason = (response.json() or {}).get("code", "")
        except Exception:
            pass
        counts[f"http:{code}:{reason}"] += 1


@events.report_to_master.add_listener
def on_report_to_master(client_id, data):
    data["node_counts"] = dict(counts)
    data["node_lat"] = dict(lat)
    counts.clear()
    lat.clear()


@events.worker_report.add_listener
def on_worker_report(client_id, data):
    merged.update(data.get("node_counts", {}))
    lat_merged.update(data.get("node_lat", {}))


@events.test_stop.add_listener
def on_test_stop(environment, **_):
    if environment.runner.__class__.__name__ == "WorkerRunner":
        return
    merged.update(counts)
    counts.clear()
    os.makedirs("results", exist_ok=True)
    path = f"results/{PROFILE}_node_counts.csv"
    with open(path, "w", encoding="utf-8") as f:
        f.write("key,count\n")
        for k, v in sorted(merged.items()):
            f.write(f"{k},{v}\n")
    print(f"[node counts] {path}")
    lat_merged.update(lat)
    lat.clear()
    per = {}
    for k, v in lat_merged.items():
        node, ms = k.rsplit("|", 1)
        per.setdefault(node, Counter())[int(ms)] += v
    path = f"results/{PROFILE}_node_latency.csv"
    with open(path, "w", encoding="utf-8") as f:
        f.write("node,count,p50_ms,p95_ms,p99_ms,max_ms\n")
        for node, h in sorted(per.items()):
            total, acc, q = sum(h.values()), 0, {}
            for ms in sorted(h):
                acc += h[ms]
                for name, frac in (("p50", .5), ("p95", .95), ("p99", .99)):
                    if name not in q and acc >= total * frac:
                        q[name] = ms
            f.write(f"{node},{total},{q['p50']},{q['p95']},{q['p99']},{max(h)}\n")
    print(f"[node latency] {path}")


# ── 공통 동작 ────────────────────────────────────────────────────────
def ok(r):
    """연결 오류 응답에서 r.ok를 읽으면 예외가 다시 던져지므로 직접 판정한다."""
    return getattr(r, "error", None) is None and 200 <= (r.status_code or 0) < 300


def clinic_days(start, n):
    """start부터 진료일(일요일 제외) n일"""
    days, d = [], start
    while len(days) < n:
        if d.weekday() != 6:
            days.append(d)
        d += timedelta(days=1)
    return days


class OwnerBase(HttpUser):
    abstract = True

    def on_start(self):
        self.account = take_account(self.environment)
        self.pets, self.reservations, self.logged_in = [], [], False
        if self.account is None:  # 계정이 모자라면 이 사용자는 멈춘다
            raise StopUser()
        self.ensure_login()

    def ensure_login(self):
        """로그인과 반려동물 목록. 스파이크 중 실패해도 다음 task에서 다시 시도한다."""
        if self.logged_in:
            return True
        r = self.client.post("/api/auth/login", name="/api/auth/login",
                             json={"loginId": f"owner{self.account:03d}", "password": PASSWORD})
        if not ok(r):
            return False
        p = self.client.get("/api/pets", name="/api/pets")
        if ok(p):
            self.pets = [x["petId"] for x in p.json()]
        self.logged_in = True
        return self.logged_in

    def on_stop(self):
        if getattr(self, "account", None) is not None:
            self.client.post("/api/auth/logout", name="/api/auth/logout")
            return_account(self.account)

    def book(self, day, visit_type, prefer_early=False, retries=3):
        """예약 가능 시간을 조회해 신청한다. 409는 정상 경합으로 보고 다른 시간으로 재시도."""
        if not self.ensure_login() or not self.pets:
            return None
        r = self.client.get(f"/api/slots?date={day.isoformat()}&type={visit_type}", name="/api/slots")
        if not ok(r):
            return None
        slots = [s["slotId"] for s in r.json()]
        pet = random.choice(self.pets)
        for _ in range(retries + 1):
            if not slots:
                return None
            pick = slots[0] if prefer_early else random.choice(slots[:10])
            slots.remove(pick)
            with self.client.post("/api/reservations", name="/api/reservations",
                                  json={"petId": pet, "slotId": pick}, catch_response=True) as res:
                if res.status_code == 201:
                    rid = res.json()["reservationId"]
                    self.reservations.append(rid)
                    return rid
                if res.status_code == 409:  # 이미 예약된 시간 또는 같은 날 중복
                    res.success()
                    counts["contention:409"] += 1
                    continue
                res.failure(f"unexpected {res.status_code}")
                return None
        return None


# ── 사용자 유형 ──────────────────────────────────────────────────────
class VisitorUser(HttpUser):
    """방문자: 로그인 없이 병원 소개와 공지를 본다."""
    weight = 3
    wait_time = between(3 * WAIT, 8 * WAIT)

    @task(3)
    def pages(self):
        self.client.get(random.choice(["/", "/about", "/doctors"]), name="정적 페이지")

    @task(2)
    def notices(self):
        r = self.client.get("/api/notices", name="/api/notices")
        if ok(r) and r.json():
            nid = random.choice(r.json())["noticeId"]
            self.client.get(f"/api/notices/{nid}", name="/api/notices/{id}")


class OwnerUser(OwnerBase):
    """예약 보호자: 신청 → 30% 변경, 10% 취소 → 내 예약 확인."""
    weight = 2
    wait_time = between(3 * WAIT, 8 * WAIT)

    @task
    def reserve(self):
        days = clinic_days(date.today() + timedelta(days=1), 12)
        rid = self.book(random.choice(days), random.choice(["GENERAL", "VACCINE", "CHECKUP"]))
        if rid is None:
            return
        roll = random.random()
        if roll < 0.30:
            day = random.choice(days)
            r = self.client.get(f"/api/slots?date={day.isoformat()}&type=GENERAL", name="/api/slots")
            if ok(r) and r.json():
                with self.client.put(f"/api/reservations/{rid}", name="/api/reservations/{id}",
                                     json={"slotId": random.choice(r.json())["slotId"]}, catch_response=True) as res:
                    if res.status_code == 409:
                        res.success()
                        counts["contention:409"] += 1
        elif roll < 0.40:
            self.client.delete(f"/api/reservations/{rid}", name="/api/reservations/{id}")
            self.reservations.remove(rid)
        self.client.get("/api/reservations/me", name="/api/reservations/me")


class EventOwnerUser(OwnerBase):
    """이벤트 보호자: 할인 기간 예방접종의 앞쪽 시간을 노린다. 스파이크 구간에만 생성."""
    weight = 1
    wait_time = between(1 * WAIT, 3 * WAIT)

    @task
    def reserve_event(self):
        if self.reservations:  # 이미 잡았으면 내 예약만 확인
            self.client.get("/api/reservations/me", name="/api/reservations/me")
            return
        day = random.choice(clinic_days(EVENT_START, EVENT_DAYS))
        self.book(day, "VACCINE", prefer_early=True, retries=3)


class AdminUser(HttpUser):
    """간호사(문서의 관리자) 2명 고정: 예약 현황 조회 → REQUESTED 승인."""
    fixed_count = 2
    wait_time = between(8, 12)
    _seq = 0

    def on_start(self):
        AdminUser._seq += 1
        self.client.post("/api/auth/login", name="/api/auth/login (admin)",
                         json={"loginId": f"admin{(AdminUser._seq - 1) % 2 + 1}", "password": PASSWORD})

    @task
    def approve(self):
        day = date.today() + timedelta(days=random.randint(1, 14))
        r = self.client.get(f"/api/admin/reservations?date={day.isoformat()}", name="/api/admin/reservations")
        if not ok(r):
            return
        for item in [x for x in r.json() if x["status"] == "REQUESTED"][:3]:
            with self.client.post(f"/api/admin/reservations/{item['reservationId']}/approve",
                                  name="/api/admin/reservations/{id}/approve", catch_response=True) as res:
                if res.status_code == 409:  # 그 사이 보호자가 취소함
                    res.success()


class WebUser(HttpUser):
    """WEB 계층 전용 방문자: nginx가 직접 응답하는 정적 HTML·CSS·JS·SVG와 SPA 묶음만 요청한다 (/api 없음 → WAS·DB 미사용).
    처음 방문(캐시 없음)이면 페이지와 함께 자산 파일을 받고, 이후 방문은 70% 확률로 캐시를 쓴다고 본다."""
    wait_time = between(3 * WAIT, 8 * WAIT)
    PAGES = ["/", "/about", "/doctors", "/services", "/notices"]
    SITE_ASSETS = ["/assets/css/base.css", "/assets/css/site.css", "/assets/js/site.js", "/assets/img/icons.svg",
                   "/assets/img/hero-pets.svg", "/assets/img/map.svg", "/assets/img/vet-1.svg", "/assets/img/vet-2.svg", "/assets/img/vet-3.svg"]

    def on_start(self):
        self.cached = False
        self.app_assets = []
        r = self.client.get("/app/", name="WEB SPA index")
        if ok(r):
            import re
            self.app_assets = sorted(set(re.findall(r'(?:src|href)="(/app/assets/[^"]+)"', r.text)))

    def _assets(self, paths, name):
        if self.cached and random.random() < 0.7:
            return
        for a in paths:
            self.client.get(a, name=name)

    @task(7)
    def page(self):
        self.client.get(random.choice(self.PAGES), name="WEB 정적 페이지")
        self._assets(self.SITE_ASSETS, "WEB 정적 자산")
        self.cached = True

    @task(3)
    def spa(self):
        self.client.get(random.choice(["/app/", "/app/login", "/app/reserve"]), name="WEB SPA index")
        self._assets(self.app_assets, "WEB SPA 자산")


# ── 부하 형태 ────────────────────────────────────────────────────────
BASE = [VisitorUser, OwnerUser, AdminUser]
WEB = [WebUser]
EVENT = [EventOwnerUser]
PROFILES = {
    # (끝나는 시각 초, 사용자 수, 초당 증감 수, 이 구간에 늘리거나 줄일 사용자 클래스)
    "tc02": [(900, 40, 4, BASE)],
    "spike": [(300, 40, 4, BASE),          # 평상시 기준값
              (330, 140, 3.4, EVENT),      # 09:00 이벤트 오픈: 30초 안에 +100 (TC-03)
              (2130, 140, 3.4, EVENT),     # 유지 (TC-03 → TC-04)
              (2160, 40, 3.4, EVENT),      # 감소: 이벤트 사용자만 내보낸다 (TC-05)
              (3660, 40, 4, BASE)],        # 정상화 관찰
    "tc06": [(900, 40, 4, BASE)],          # 5분·10분 시점 장애 주입은 사람이 수행
    "tc08": [(180 * (i + 1), 140 + 40 * i, 5, BASE) for i in range(6)],  # 140→340, 3분마다 +40
    # 과부하 지점 찾기 (오토스케일링 없는 고정 WEB 2·WAS 2). 보호자 계정은 300개라 그 이상은 방문자로 채워진다
    "stress": [(STRESS_STEP_SEC * (i + 1), STRESS_STEP * (i + 1), 10, BASE) for i in range(STRESS_STEPS)],
    # ── WEB 계층 전용 (문서 03장 기준: 정적 p95 300ms 미만, 분산 ±20%, CPU 70% 미만, 장애 시 10초 안에 대상 제외) ──
    "web02": [(900, 40, 4, WEB)],                       # W-1 기준선 = TC-02 (40명 15분)
    "webspike": [(300, 40, 4, WEB),                     # W-2 = TC-03~05: 평상시 5분
                 (330, 140, 3.4, WEB),                  #   30초 안에 140명 (TC-03)
                 (1530, 140, 3.4, WEB),                 #   140명 20분 유지 (TC-04)
                 (1560, 40, 3.4, WEB),                  #   감소 (TC-05)
                 (1860, 40, 4, WEB)],                   #   정상화 5분 관찰
    "web06": [(900, 40, 4, WEB)],                       # W-3 = TC-06 ②: 5분에 WEB-a nginx 중지, 7분에 재시작 (aws.sh fault)
    "webstress": [(STRESS_STEP_SEC * (i + 1), STRESS_STEP * (i + 1), 10, WEB) for i in range(STRESS_STEPS)],  # W-4 과부하
}


class VetShape(LoadTestShape):
    def tick(self):
        t = self.get_run_time() / TIME_SCALE
        for end, users, rate, classes in PROFILES[PROFILE]:
            if t < end:
                return users, rate / TIME_SCALE, classes
        return None
