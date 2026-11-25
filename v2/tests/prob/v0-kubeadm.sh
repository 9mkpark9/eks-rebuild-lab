#!/usr/bin/env bash
# K-1 ~ K-4 재현: 가장 단순한 배포(v2/k8s/v0/all.yaml)를 kubeadm 에 따로 띄운다 (네임스페이스 vet2-v0).
#   v2/tests/prob/v0-kubeadm.sh up     띄운다. 웹은 NodePort 30081 (그동안 vet2-rds 의 웹은 ClusterIP 로 잠시 닫는다)
#   v2/tests/prob/v0-kubeadm.sh down   지우고 vet2-rds 의 웹을 원래대로 (NodePort 30081)
# v0/all.yaml 은 고치지 않는다. 렌더한 파일(비밀번호가 들어 있다)은 v2/_run/ 에만 만든다.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"; cd "$ROOT"
OUT="$ROOT/v2/_run/3-k8s/v0-kubeadm.yaml"; command -v cygpath > /dev/null && OUT="$(cygpath -m "$OUT")"
# ECR 주소는 이미 떠 있는 vet2 의 이미지 주소에서 얻는다 (AWS 로그인 없이)
REG="$(kubectl -n vet2 get deploy auth -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's#/vet2-auth:.*##')"
case "${1:-}" in
up)
    kubectl -n vet2-rds patch svc web -p '{"spec":{"type":"ClusterIP","ports":[{"port":80,"targetPort":8080,"nodePort":null}]}}' > /dev/null
    set -a; . v2/_run/secrets.env; set +a
    envsubst < v2/k8s/v0/all.yaml | sed -e 's/namespace: vet2$/namespace: vet2-v0/' -e 's/namespace: vet2 }/namespace: vet2-v0 }/' -e 's/^  name: vet2$/  name: vet2-v0/' \
        -e "s#image: vet2-\([a-z]*\):1.0.0#image: $REG/vet2-\1:1.0.0#" \
        -e 's/type: LoadBalancer/type: NodePort/' -e 's/port: 28080, targetPort: 8080/port: 80, targetPort: 8080, nodePort: 30081/' > "$OUT"
    if grep -E "namespace: [a-z0-9-]+" -o "$OUT" | grep -qv "namespace: vet2-v0"; then echo "vet2-v0 가 아닌 네임스페이스가 있다. 멈춘다" >&2; exit 1; fi
    kubectl create ns vet2-v0 > /dev/null 2>&1
    # ECR 로그인 Secret 은 vet2 의 것을 복사해 쓴다 (12시간 유효, K-5)
    kubectl -n vet2 get secret ecr-pull -o json | sed 's/"namespace": "vet2"/"namespace": "vet2-v0"/' | grep -v '"resourceVersion"\|"uid"\|"creationTimestamp"' | kubectl apply -f - > /dev/null
    kubectl -n vet2-v0 patch serviceaccount default -p '{"imagePullSecrets":[{"name":"ecr-pull"}]}' > /dev/null
    kubectl apply -f "$OUT"
    for d in mysql redis auth clinic reservation web; do kubectl -n vet2-v0 rollout status deploy/$d --timeout=300s > /dev/null; done
    # DB 는 처음 뜰 때 스스로 초기화한다 (② C-8). 공지 조회가 200 이 될 때까지 기다린다
    W=$(kubectl get node vet2-w1 -o jsonpath='{.status.addresses[?(@.type=="ExternalIP")].address}')
    [ -n "$W" ] || W="${W1:-}"
    for i in $(seq 1 90); do [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://$W:30081/api/notices")" = 200 ] && break; sleep 2; done
    echo "DB 초기화까지 기다린 시간: 약 $((i * 2))초"
    kubectl -n vet2-v0 get pods
    ;;
down)
    kubectl delete ns vet2-v0 --wait=true > /dev/null 2>&1
    # 원래 매니페스트와 같은 NodePort 30081 로 되돌린다 (apply.sh 는 AWS 로그인이 필요해 직접 고친다)
    kubectl -n vet2-rds patch svc web -p '{"spec":{"type":"NodePort","ports":[{"name":"http","port":80,"targetPort":"http","nodePort":30081}]}}' > /dev/null
    rm -f "$OUT"
    kubectl -n vet2-rds get svc web
    ;;
*) sed -n 2,5p "$0"; exit 2 ;;
esac
