"""Locust 결과 요약 (Locust EC2의 /opt/loadtest 에서 실행): python3 summarize.py <프로필>

- 사용자 수 단계별 RPS · 실패율 · p95/p99 (results/<프로필>_stats_history.csv 의 Aggregated 행)
- 한계 지점: p95 가 기준(인자 2, 기본 1000ms·WEB 300ms) 이상이거나 실패율이 1% 이상이 된 첫 단계
- 요청별 최종 통계, 실패 상위 5개, WEB·WAS 분산 건수
"""
import csv
import os
import statistics
import sys

p = sys.argv[1] if len(sys.argv) > 1 else "stress"
LIMIT_MS = float(sys.argv[2]) if len(sys.argv) > 2 else 1000.0  # WEB 정적 기준은 300ms
base = os.path.join("results", p)


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def rows(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


hist = [r for r in rows(base + "_stats_history.csv") if r.get("Name") == "Aggregated"]
steps = {}
for r in hist:
    u = int(num(r.get("User Count")) or 0)
    if u == 0:
        continue
    steps.setdefault(u, []).append(r)

print(f"== {p}: 사용자 수 단계별 (stats_history, Aggregated) ==")
print("users,초수,평균RPS,평균실패/s,실패율%,p95중앙ms,p95최대ms,p99중앙ms")
limit = None
for u in sorted(steps):
    rs = steps[u]
    if len(rs) < 5:  # 사용자를 늘리는 도중 1~2초만 거친 중간 값은 단계로 보지 않는다
        continue
    rps = [x for x in (num(r.get("Requests/s")) for r in rs) if x is not None]
    fps = [x for x in (num(r.get("Failures/s")) for r in rs) if x is not None]
    p95 = [x for x in (num(r.get("95%")) for r in rs) if x is not None]
    p99 = [x for x in (num(r.get("99%")) for r in rs) if x is not None]
    a_rps = statistics.mean(rps) if rps else 0
    a_fps = statistics.mean(fps) if fps else 0
    fail = (a_fps / a_rps * 100) if a_rps else 0
    m95 = statistics.median(p95) if p95 else 0
    x95 = max(p95) if p95 else 0
    m99 = statistics.median(p99) if p99 else 0
    print(f"{u},{len(rs)},{a_rps:.1f},{a_fps:.2f},{fail:.2f},{m95:.0f},{x95:.0f},{m99:.0f}")
    if limit is None and (m95 >= LIMIT_MS or fail >= 1):
        limit = (u, a_rps, m95, fail)
if limit:
    print(f"LIMIT: 사용자 {limit[0]}명(평균 {limit[1]:.1f} RPS)에서 기준 초과 — p95 {limit[2]:.0f}ms, 실패율 {limit[3]:.2f}%")
elif steps:
    print(f"LIMIT: 모든 단계에서 p95 {LIMIT_MS:.0f}ms 미만, 실패율 1% 미만 (한계에 닿지 않음)")
else:
    print("LIMIT: 아직 기록 없음")

print(f"\n== {p}: 요청별 최종 통계 (stats.csv) ==")
print("이름,요청,실패,중앙ms,평균ms,RPS,p95ms,p99ms")
for r in rows(base + "_stats.csv"):
    print(",".join([r.get("Name", ""), r.get("Request Count", ""), r.get("Failure Count", ""),
                    r.get("Median Response Time", ""), f"{num(r.get('Average Response Time')) or 0:.0f}",
                    f"{num(r.get('Requests/s')) or 0:.1f}", r.get("95%", ""), r.get("99%", "")]))

fails = sorted(rows(base + "_failures.csv"), key=lambda r: -int(num(r.get("Occurrences")) or 0))[:5]
if fails:
    print(f"\n== {p}: 실패 상위 5 ==")
    for r in fails:
        print(f"{r.get('Occurrences')}회  {r.get('Method')} {r.get('Name')}  {r.get('Error', '')[:120]}")

lat = rows(base + "_node_latency.csv")
if lat:
    print(f"\n== {p}: 노드별 응답 시간 (WEB: 노드 이름, WAS: was:노드 이름) ==")
    print("node,count,p50_ms,p95_ms,p99_ms,max_ms")
    for r in lat:
        print(",".join(r[k] for k in ("node", "count", "p50_ms", "p95_ms", "p99_ms", "max_ms")))

nodes = rows(base + "_node_counts.csv")
if nodes:
    print(f"\n== {p}: 분산 (X-Web-Node / X-Served-By) ==")
    for r in nodes:
        print(f"{r.get('key')},{r.get('count')}")
