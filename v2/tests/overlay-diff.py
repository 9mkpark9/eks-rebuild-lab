"""Kustomize overlay 마다 무엇이 다른지 한 줄씩 뽑는다 (kubectl kustomize 결과에서).
   python v2/tests/overlay-diff.py
"""
import subprocess

ROWS = ["local", "kubeadm", "eks", "kubeadm-rds", "eks-rds"]


def docs(overlay):
    out = subprocess.run(["kubectl", "kustomize", f"v2/k8s/overlays/{overlay}"], capture_output=True, text=True, encoding="utf-8", check=True).stdout
    return [d for d in out.split("\n---\n")]


def field(doc, key):
    for line in doc.splitlines():
        s = line.strip()
        if s.startswith(key + ":"):
            return s.split(":", 1)[1].strip()
    return ""


print(f"{'overlay':<12} {'네임스페이스':<10} {'웹을 여는 법':<22} {'DB':<22} {'볼륨':<11} {'초기화 Job':<8} {'DB 연결 수'}")
for o in ROWS:
    ds = docs(o)
    kinds = [(field(d, "kind"), field(d, "name"), d) for d in ds]
    ns = next((field(d, "namespace") for k, n, d in kinds if k == "Deployment"), "")
    svc = next((d for k, n, d in kinds if k == "Service" and n == "web"), "")
    typ = field(svc, "type") or "ClusterIP"
    port = field(svc, "nodePort")
    expose = {"NodePort": f"NodePort {port}", "LoadBalancer": "LoadBalancer :28080"}.get(typ, "")
    if any(k == "Ingress" for k, _, _ in kinds):
        expose = "Ingress → ALB"
    cm = next((d for k, n, d in kinds if k == "ConfigMap"), "")
    db = field(cm, "DB_HOST")
    db = "RDS (사설 서브넷)" if db == "RDS_HOST" else "mysql (StatefulSet)"
    vol = next((field(d, "storageClassName") for k, n, d in kinds if k == "StatefulSet"), "") or ("기본(standard)" if "StatefulSet" in [k for k, _, _ in kinds] else "-")
    job = "있음" if any(k == "Job" for k, _, _ in kinds) else "-"
    pool = field(cm, "DB_POOL_MAX").strip('"')
    print(f"{o:<12} {ns:<10} {expose:<22} {db:<22} {vol:<11} {job:<8} {pool}")
