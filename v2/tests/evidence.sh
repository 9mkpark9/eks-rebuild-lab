#!/usr/bin/env bash
# 문서 표의 숫자를 낸 원본 출력(v2/_run/ 의 실행 기록)에서 근거 캡처를 만든다. 숫자를 다시 재지 않고, 그때의 출력을 그대로 옮긴다.
# 각 캡처의 머리에 원본 파일과 실행 시각(파일 시각)을 적는다. 그림은 v2/tests/render.mjs 가 만든다.
#   v2/tests/evidence.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; cd "$ROOT"
. v2/tests/cap.sh
R=v2/_run
# ev <이름> <제목> <원본 파일> [grep -E 패턴]   패턴이 있으면 그 줄만, 없으면 전부
ev() {
    local name="$1" title="$2" f="$3" pat="${4:-}"
    [ -f "$R/$f" ] || { echo "없음: $f" >&2; return 1; }
    local note="실행 기록 $(date -r "$R/$f" '+%Y-%m-%d %H:%M') · 원본 v2/_run/$f"
    if [ -n "$pat" ]; then grep -E "$pat" "$R/$f"; else cat "$R/$f"; fi | cap_note "$name" "$title" "$note"
    echo "기록: $name"
}
OPS='■|트래픽|^      /|만든 예약|통과\]|실패\]|까지|버전'

# ② 종료 신호 (C-4)
ev ev2-shutdown "② C-4: 요청 중에 서비스를 내렸을 때 (동시 20개)" 2-container/shutdown.log
# ③ v0 와 최종 (K-1 ~ K-4)
ev ev3-v0-ops "③ v0: 배포·업데이트·Pod 삭제·DB 교체 중 실패 (K-1, K-2)" 3-k8s/v0-ops.log "$OPS"
ev ev3-v0-extra "③ v0: 비밀번호 노출, 자원 등급 (K-3, K-4)" 3-k8s/v0-extra.log '■|줄:|BestEffort|Burstable'
ev ev3-final-ops "③ 최종 (EC2 kubeadm): 배포·업데이트·Pod 삭제·DB 교체" rds/ops-required-kubeadm.txt "$OPS"
# ③ 노드 장애 (K-8 ~ K-11)
ev ev3-node-w2-before "③ 워커2 강제 중지, 고치기 전 (K-8, K-9)" 3-k8s/ec2-node-down.log '^\+|트래픽'
ev ev3-node-w2-after "③ 워커2 강제 중지, 고친 뒤 (tolerationSeconds 30, matchLabelKeys)" 3-k8s/ec2-node-down-2.log '^\+|트래픽'
ev ev3-node-w1-before "③ 워커1(MySQL) 강제 중지, CoreDNS 고치기 전 (K-10)" 3-k8s/ec2-node-down-w1.log '^\+|트래픽|응답 없음|^    /'
ev ev3-node-w1-after "③ 워커1(MySQL) 강제 중지, CoreDNS 고친 뒤 (K-11)" 3-k8s/ec2-node-down-w1b.log '^\+|트래픽|^    /|DB 가 필요'
# ④ EKS 최종
ev ev4-final-ops "④ 최종 (EKS): 배포·업데이트·Pod 삭제·DB 교체" rds/ops-required-eks.txt "$OPS"
# ⑥ RDS
ev ev6-pool5-eks "⑥ RDS 연결 수 5 일 때 (EKS): 배포 중 실패" rds/ops-eks.txt "$OPS"
ev ev6-pool3-kubeadm "⑥ RDS 연결 수 3, 두 클러스터 동시 측정 (kubeadm)" rds/ops-pool3-kubeadm.txt "$OPS"
ev ev6-pool3-eks "⑥ RDS 연결 수 3, 두 클러스터 동시 측정 (EKS)" rds/ops-pool3-eks.txt "$OPS"
ev ev6-reboot "⑥ RDS 재시작 뒤 데이터 유지 (사설 서브넷, EKS 에서 명령)" rds/reboot2-eks.txt
ev ev6-reboot-kubeadm "⑥ RDS 재시작 동안 kubeadm 쪽 요청 (같은 시간)" rds/reboot2-kubeadm.txt '트래픽|^    /'
ev ev6-node-w1 "⑥ 워커1 강제 중지 (DB 는 RDS)" rds/node-w1.txt
