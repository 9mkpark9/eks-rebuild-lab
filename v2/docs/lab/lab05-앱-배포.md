# [실습] lab05: 앱 배포

| 속성 | 값 |
|---|---|
| 상위 항목 | ③ 쿠버네티스 전환 |
| 선행 작업 | [lab04: kubeadm 클러스터 구축](lab04-kubeadm-클러스터-구축.md) |
| 후속 작업 | [lab06: 배포 운영](lab06-배포-운영.md) |

lab04 의 클러스터에 앱 6개(web, 서비스 3개, MySQL, Redis)를 올린다. 비밀번호는 Secret, 그 밖의 설정은 ConfigMap 으로 넣고, 이미지는 ECR 에서 받는다. Kustomize 로 환경별 차이를 채워 적용한 뒤, 복제본이 두 노드에 나뉘고 밖에서 NodePort 로 접속되며 배포 정보에 비밀번호가 없는 것을 확인한다.

## 실습 목표

- Secret 두 개(DB, Redis)를 파일을 남기지 않고 만든다
- kubeadm 노드가 ECR 에서 이미지를 받을 수 있게 로그인 Secret 을 기본 ServiceAccount 에 붙인다
- Kustomize overlay 를 렌더해 자리 표시를 채우고 적용한다
- 복제본 2개가 두 노드에 나뉘고, MySQL 볼륨이 lab04 의 PV 에 묶이는 것을 확인한다
- 밖에서 NodePort 로 접속해 시나리오 테스트(65개 항목)를 통과시킨다
- 배포 정보(Deployment, StatefulSet, ConfigMap)에 비밀번호 값이 없는 것을 확인한다

## 사전 준비

| 항목 | 내용 | 비고 |
|---|---|---|
| 클러스터 | lab04 의 kubeadm 클러스터 (3노드 Ready, StorageClass `vet2-local`) | |
| 실행 위치 | 이 PC (kubectl, AWS CLI) | `KUBECONFIG=v2/_run/kubeconfig-kubeadm` |
| 이미지 | ECR 의 `vet2-auth·clinic·reservation·web:1.0.0`, `vet2-db:1.1.0`, `redis:7-alpine` | lab03 에서 올렸다 |
| Namespace | `vet2` | |
| 변수 | lab03 의 `REG`, `MY_CIDR`, lab04 의 `KUBECONFIG` | |
| 작업 디렉터리 | `~/vet2-lab` | |

```bash
$ W1=$(aws ec2 describe-instances --filters Name=tag:Name,Values=vet2-w1 Name=instance-state-name,Values=running \
       --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
```

`W1` 은 워커1 의 공인 IP 다. 이 문서의 출력에서는 `<W1 공인 IP>` 로 가렸다.

## 1. Secret

### 1. DB 와 Redis 비밀번호

```bash
$ set -a; . v2/_run/secrets.env; set +a
$ kubectl create namespace vet2
# 출력 예
namespace/vet2 created

$ kubectl -n vet2 create secret generic vet-db \
    --from-literal=root-password="$DB_ROOT_PASSWORD" --from-literal=auth-password="$DB_AUTH_PASSWORD" \
    --from-literal=clinic-password="$DB_CLINIC_PASSWORD" --from-literal=reservation-password="$DB_RESERVATION_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
# 출력 예
secret/vet-db created

$ kubectl -n vet2 create secret generic vet-redis --from-literal=password="$REDIS_PASSWORD" --dry-run=client -o yaml | kubectl apply -f -
# 출력 예
secret/vet-redis created
```

`--dry-run=client -o yaml` 은 Secret 을 만들지 않고 YAML 로 출력만 한다. 그것을 파이프로 바로 `apply` 에 넘기므로 비밀번호가 든 파일이 디스크에 남지 않는다. `create` 대신 `apply` 로 넘기는 것은 다시 실행해도 "이미 있다" 로 실패하지 않게 하려는 것이다.

### 2. 확인

```bash
$ kubectl -n vet2 get secret
# 출력 예
NAME        TYPE     DATA   AGE
vet-db      Opaque   4      6s
vet-redis   Opaque   1      4s

$ kubectl -n vet2 describe secret vet-db | tail -7
# 출력 예

Data
====
auth-password:         36 bytes
clinic-password:       36 bytes
reservation-password:  36 bytes
root-password:         36 bytes
```

`describe` 는 값을 보여 주지 않고 길이만 보여 준다. Secret 의 값은 base64 로만 바뀌어 저장되므로, Secret 을 읽을 권한이 있는 사람은 값을 볼 수 있다. 이 클러스터는 Secret 을 암호화해 저장하지 않는다 (③ 한계).

### 3. ECR 로그인 Secret

```bash
$ kubectl -n vet2 create secret docker-registry ecr-pull --docker-server=$REG --docker-username=AWS \
    --docker-password="$(aws ecr get-login-password)" --dry-run=client -o yaml | kubectl apply -f -
# 출력 예
secret/ecr-pull created

$ kubectl -n vet2 patch serviceaccount default -p '{"imagePullSecrets":[{"name":"ecr-pull"}]}'
# 출력 예
serviceaccount/default patched

$ kubectl -n vet2 get serviceaccount default -o jsonpath="{.imagePullSecrets}"; echo
# 출력 예
[{"name":"ecr-pull"}]
```

kubeadm 의 kubelet 은 노드의 IAM 역할로 ECR 에 로그인하지 않는다. 이 Secret 이 없으면 Pod 가 `ImagePullBackOff` 로 멈춘다 (③ K-5). 기본 ServiceAccount 에 붙이면 이 Namespace 의 모든 Pod 가 따로 적지 않아도 이것으로 이미지를 받는다.

ECR 로그인 비밀번호는 **12시간 뒤 만료된다.** 그 뒤 새 Pod 가 이미지를 받으려면 이 두 명령을 다시 실행한다. 이미 받아 둔 이미지로 도는 Pod 는 영향이 없다. EKS(lab07)에서는 이 단계가 필요 없다.

### 4. 결과 확인

| 항목 | 내용 |
|---|---|
| `vet-db` | 비밀번호 4개 (root, 서비스 계정 3) |
| `vet-redis` | 비밀번호 1개 |
| `ecr-pull` | ECR 로그인, 12시간, 기본 ServiceAccount 에 붙임 |

## 2. 매니페스트

### 1. 구성

```
v2/k8s/
├── base/            환경과 무관한 공통: web, auth, clinic, reservation, redis, PDB, ConfigMap
├── mysql/           클러스터 안 MySQL (StatefulSet + Service)
└── overlays/
    └── kubeadm/     이 클러스터에만 다른 것: Namespace, web 을 NodePort 로, 볼륨 종류, 이미지 주소
```

### 2. 서비스 Deployment (clinic)

① `v2/k8s/base/clinic.yaml` 에서 Deployment 부분 (auth, reservation 은 이름과 DB 스키마·계정만 다르다)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: clinic
  labels: { app: clinic }
spec:
  replicas: 2
  selector: { matchLabels: { app: clinic } }
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxSurge: 1, maxUnavailable: 0 }
  template:
    metadata:
      labels: { app: clinic }
    spec:
      terminationGracePeriodSeconds: 45
      securityContext:
        runAsNonRoot: true
        seccompProfile: { type: RuntimeDefault }
      tolerations:
        - { key: node.kubernetes.io/not-ready, operator: Exists, effect: NoExecute, tolerationSeconds: 30 }
        - { key: node.kubernetes.io/unreachable, operator: Exists, effect: NoExecute, tolerationSeconds: 30 }
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          nodeTaintsPolicy: Honor
          labelSelector: { matchLabels: { app: clinic } }
          matchLabelKeys: [pod-template-hash]
      containers:
        - name: clinic
          image: vet2-clinic
          ports: [{ name: http, containerPort: 8080 }]
          envFrom:
            - configMapRef: { name: vet-config }
          env:
            - { name: SPRING_DATASOURCE_URL, value: "jdbc:mysql://$(DB_HOST):3306/vet_clinic?connectionTimeZone=LOCAL&characterEncoding=UTF-8" }
            - { name: SPRING_DATASOURCE_USERNAME, value: vet_clinic }
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom: { secretKeyRef: { name: vet-db, key: clinic-password } }
            - name: SPRING_DATA_REDIS_PASSWORD
              valueFrom: { secretKeyRef: { name: vet-redis, key: password } }
          startupProbe:
            httpGet: { path: /health, port: http }
            periodSeconds: 2
            failureThreshold: 60
          readinessProbe:
            httpGet: { path: /health, port: http }
            periodSeconds: 5
            failureThreshold: 2
          livenessProbe:
            httpGet: { path: /health, port: http }
            periodSeconds: 10
            failureThreshold: 3
          lifecycle:
            preStop:
              exec: { command: ["sleep", "5"] }
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits: { cpu: "1", memory: 384Mi }
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: { drop: ["ALL"] }
          volumeMounts:
            - { name: tmp, mountPath: /tmp }
      volumes:
        - { name: tmp, emptyDir: {} }
```

| 설정 | 왜 |
|---|---|
| `replicas: 2`, `maxSurge: 1`, `maxUnavailable: 0` | 새 Pod 가 준비된 뒤에 옛 Pod 를 내린다. 배포 중에도 요청을 받을 Pod 가 늘 있다 (lab06) |
| `startupProbe` (2초 × 60) | JVM 이 뜨는 동안(4 ~ 10초)은 이것만 본다. 통과하기 전에는 liveness 가 Pod 를 재시작하지 않는다 |
| `readinessProbe` | 통과한 Pod 만 Service 의 요청 대상이 된다 |
| `livenessProbe` (10초 × 3) | 30초 동안 응답이 없으면 컨테이너를 다시 시작한다. `/health` 는 DB 를 보지 않으므로 DB 장애로 재시작되지 않는다 |
| `preStop: sleep 5` | 종료 신호 전에 5초 기다린다. 그동안 Service 에서 빠진 것이 노드들에 퍼져 새 요청이 오지 않는다 |
| `topologySpreadConstraints` | 복제본을 노드에 나눈다. `matchLabelKeys` 는 배포 중 새 버전끼리만 세게 한다 |
| `tolerations` 30초 | 노드가 죽으면 기본 300초가 아니라 30초 뒤 다른 노드에서 다시 띄운다 |
| `envFrom` + `secretKeyRef` | 비밀이 아닌 설정은 ConfigMap, 비밀번호는 Secret 에서. 매니페스트에 값이 없다 |
| `resources` | 요청 256Mi 는 lab02 에서 잰 사용량(약 175MiB) 기준, 한도 384Mi 는 lab02 의 `mem_limit` 과 같다 |
| `securityContext` | root 금지, 권한 상승 금지, 루트 파일 시스템 읽기 전용. 쓰기가 필요한 `/tmp` 만 emptyDir 로 |

### 3. MySQL StatefulSet

`v2/k8s/mysql/mysql.yaml` 의 핵심:

```yaml
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql
  replicas: 1
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
        runAsGroup: 999
        fsGroup: 999
      containers:
        - name: mysql
          image: vet2-db
          env:
            - name: MYSQL_ROOT_PASSWORD
              valueFrom: { secretKeyRef: { name: vet-db, key: root-password } }
            # DB_AUTH_PASSWORD, DB_CLINIC_PASSWORD, DB_RESERVATION_PASSWORD 도 같은 방식
          startupProbe:
            exec: { command: ["sh", "-c", "MYSQL_PWD=\"$DB_CLINIC_PASSWORD\" mysql -h127.0.0.1 -uvet_clinic -e 'SELECT 1 FROM vet_clinic.vets LIMIT 1'"] }
            periodSeconds: 3
            failureThreshold: 60
          volumeMounts:
            - { name: data, mountPath: /var/lib/mysql }
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        accessModes: [ReadWriteOnce]
        resources: { requests: { storage: 2Gi } }
```

| 설정 | 왜 |
|---|---|
| StatefulSet | 같은 이름(`mysql-0`)의 Pod 를 한 번에 하나만 두고, 옛 Pod 가 완전히 끝난 뒤 새 Pod 를 띄운다. 두 MySQL 이 같은 데이터를 동시에 쓰지 않는다 |
| `volumeClaimTemplates` | `data-mysql-0` 이라는 PVC 를 만들어 Pod 에 붙인다. Pod 를 지워도 PVC 와 데이터는 남는다 |
| probe | TCP 로, 서비스 계정으로 시드를 읽어야 준비된 것이다. 초기화 중의 임시 서버에 속지 않는다 (lab01) |
| `fsGroup: 999` | 볼륨의 파일을 mysql 사용자가 쓸 수 있게 한다 |

Service `mysql` 은 `ClusterIP` 다. 클러스터 안에서만 닿는다.

### 4. overlay (kubeadm)

① `v2/k8s/overlays/kubeadm/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: vet2
resources:
  - namespace.yaml
  - ../../base
  - ../../mysql
patches:
  - target:
      kind: Service
      name: web
    patch: |-
      - { op: replace, path: /spec/type, value: NodePort }
      - { op: add, path: /spec/ports/0/nodePort, value: 30080 }
  - target: { kind: StatefulSet, name: mysql }
    patch: |-
      - { op: add, path: /spec/volumeClaimTemplates/0/spec/storageClassName, value: vet2-local }
images:
  - { name: vet2-web, newName: ECR_REGISTRY/vet2-web, newTag: 1.0.0 }
  - { name: vet2-auth, newName: ECR_REGISTRY/vet2-auth, newTag: 1.0.0 }
  - { name: vet2-clinic, newName: ECR_REGISTRY/vet2-clinic, newTag: 1.0.0 }
  - { name: vet2-reservation, newName: ECR_REGISTRY/vet2-reservation, newTag: 1.0.0 }
  - { name: vet2-db, newName: ECR_REGISTRY/vet2-db, newTag: 1.1.0 }
```

| 이 overlay 가 정하는 것 | 왜 |
|---|---|
| web 을 NodePort 30080 | kubeadm 에는 LoadBalancer 를 만들어 줄 것이 없다. 노드의 30080 포트로 연다. 보안 그룹이 이 PC 의 IP 에만 연다 |
| StorageClass `vet2-local` | lab04 에서 등록한 워커1 의 디스크 |
| 이미지 주소 `ECR_REGISTRY/...` | 계정 번호가 든 실제 주소는 적용할 때 채운다 |

### 5. 결과 확인

| 항목 | 내용 |
|---|---|
| base | 환경과 무관. 다른 클러스터(EKS)에서도 그대로 쓴다 |
| overlay | 이 클러스터에만 다른 4가지 |

## 3. 적용

### 1. 렌더

```bash
$ kubectl kustomize v2/k8s/overlays/kubeadm | sed -e "s#ECR_REGISTRY#$REG#g" -e "s#MY_CIDR#$MY_CIDR#g" > v2/_run/render-kubeadm.yaml
$ grep -E "^kind:" v2/_run/render-kubeadm.yaml | sort | uniq -c
# 출력 예
      1 kind: ConfigMap
      5 kind: Deployment
      1 kind: Namespace
      4 kind: PodDisruptionBudget
      6 kind: Service
      1 kind: StatefulSet
```

`kubectl kustomize` 가 base, mysql, overlay 를 합친 최종 매니페스트를 출력한다. `sed` 로 자리 표시를 실제 값으로 바꾼다. 적용하기 전에 무엇이 들어가는지 먼저 본다. 렌더한 파일에는 계정 번호가 들어 있으므로 `v2/_run/`(Git 밖)에 두고 적용 뒤 지운다.

### 2. 적용

```bash
$ kubectl apply -f v2/_run/render-kubeadm.yaml && rm v2/_run/render-kubeadm.yaml
# 출력 예
Warning: resource namespaces/vet2 is missing the kubectl.kubernetes.io/last-applied-configuration annotation ...
namespace/vet2 configured
configmap/vet-config-8kc4g97gbt created
service/auth created
service/clinic created
service/mysql created
service/redis created
service/reservation created
service/web created
deployment.apps/auth created
deployment.apps/clinic created
deployment.apps/redis created
deployment.apps/reservation created
deployment.apps/web created
statefulset.apps/mysql created
poddisruptionbudget.policy/auth created
poddisruptionbudget.policy/clinic created
poddisruptionbudget.policy/reservation created
poddisruptionbudget.policy/web created
```

경고는 1단계에서 Namespace 를 `create` 로 만들었기 때문이다. 다음부터는 `apply` 가 관리하도록 표시를 더했다는 뜻이라 문제가 없다. ConfigMap 이름 끝의 `-8kc4g97gbt` 는 내용의 해시다. 값을 바꾸면 이름이 바뀌고, 그것을 쓰는 Pod 가 새 설정으로 다시 뜬다.

### 3. 준비 대기

```bash
$ for d in web auth clinic reservation redis; do kubectl -n vet2 rollout status deploy/$d --timeout=300s; done
$ kubectl -n vet2 rollout status sts/mysql --timeout=300s
# 출력 예
Waiting for deployment "web" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "web" rollout to finish: 1 of 2 updated replicas are available...
deployment "web" successfully rolled out
...(생략)...
deployment "redis" successfully rolled out
Waiting for 1 pods to be ready...
partitioned roll out complete: 1 new pods have been updated...
```

### 4. 결과 확인

```bash
$ kubectl -n vet2 get pods -o wide
# 출력 예
NAME                          READY   STATUS    RESTARTS   AGE   IP           NODE      ...
auth-7ff9ccdc98-447t4         1/1     Running   0          54s   10.244.2.5   vet2-w2   ...
auth-7ff9ccdc98-qqchl         1/1     Running   0          54s   10.244.1.4   vet2-w1   ...
clinic-569fc777c6-77d92       1/1     Running   0          54s   10.244.2.3   vet2-w2   ...
clinic-569fc777c6-bbxbr       1/1     Running   0          54s   10.244.1.5   vet2-w1   ...
mysql-0                       1/1     Running   0          54s   10.244.1.9   vet2-w1   ...
redis-596f7f8ddc-wbbw6        1/1     Running   0          54s   10.244.1.6   vet2-w1   ...
reservation-b7f5779db-6fln6   1/1     Running   0          54s   10.244.1.7   vet2-w1   ...
reservation-b7f5779db-z2fbs   1/1     Running   0          54s   10.244.2.4   vet2-w2   ...
web-784b5d88dc-d748d          1/1     Running   0          54s   10.244.2.6   vet2-w2   ...
web-784b5d88dc-x9rpz          1/1     Running   0          54s   10.244.1.8   vet2-w1   ...

$ kubectl -n vet2 get deploy,sts,svc,pvc
# 출력 예
NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/auth          2/2     2            2           56s
deployment.apps/clinic        2/2     2            2           56s
deployment.apps/redis         1/1     1            1           56s
deployment.apps/reservation   2/2     2            2           56s
deployment.apps/web           2/2     2            2           56s

NAME                     READY   AGE
statefulset.apps/mysql   1/1     56s

NAME                  TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
service/auth          ClusterIP   10.106.6.7       <none>        8080/TCP       56s
service/clinic        ClusterIP   10.109.149.130   <none>        8080/TCP       56s
service/mysql         ClusterIP   10.100.129.64    <none>        3306/TCP       56s
service/redis         ClusterIP   10.110.35.166    <none>        6379/TCP       56s
service/reservation   ClusterIP   10.103.152.148   <none>        8080/TCP       56s
service/web           NodePort    10.98.168.27     <none>        80:30080/TCP   56s

NAME                                 STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS   ...
persistentvolumeclaim/data-mysql-0   Bound    vet2-mysql   2Gi        RWO            vet2-local     ...

$ kubectl -n vet2 logs mysql-0 | grep "\[vet\]"
# 출력 예
[vet] 1) 스키마 4개와 서비스 계정 3개
[vet] 2) 테이블과 시드 (vet_load)
[vet] 3) 서비스별 스키마로 옮기고 권한 주기
[vet] 초기화 끝
```

| 항목 | 내용 |
|---|---|
| 복제본 | web·서비스 3개 모두 2개, vet2-w1 과 vet2-w2 에 하나씩 |
| MySQL | vet2-w1 (PV 가 그 노드에 있다). PVC `Bound`, 첫 실행 때 스스로 초기화 |
| Service | web 만 NodePort 30080, 나머지는 ClusterIP |

## 4. 확인

### 1. Probe 와 자원

```bash
$ kubectl -n vet2 describe deploy clinic | grep -E "Replicas:|StrategyType|RollingUpdateStrategy|Liveness|Readiness|Startup|Limits|Requests|cpu:|memory:"
# 출력 예
Replicas:               2 desired | 2 updated | 2 total | 2 available | 0 unavailable
StrategyType:           RollingUpdate
RollingUpdateStrategy:  0 max unavailable, 1 max surge
    Limits:
      cpu:     1
      memory:  384Mi
    Requests:
      cpu:      100m
      memory:   256Mi
    Liveness:   http-get http://:http/health delay=0s timeout=1s period=10s #success=1 #failure=3
    Readiness:  http-get http://:http/health delay=0s timeout=1s period=5s #success=1 #failure=2
    Startup:    http-get http://:http/health delay=0s timeout=1s period=2s #success=1 #failure=60
```

### 2. 설정과 비밀번호

```bash
$ kubectl -n vet2 exec deploy/clinic -- printenv DB_HOST DB_POOL_MAX SPRING_DATA_REDIS_HOST SPRING_DATASOURCE_URL
# 출력 예
mysql
5
redis
jdbc:mysql://mysql:3306/vet_clinic?connectionTimeZone=LOCAL&characterEncoding=UTF-8

$ kubectl -n vet2 get deploy clinic -o jsonpath="{.spec.template.spec.containers[0].env[2]}"; echo
# 출력 예
{"name":"SPRING_DATASOURCE_PASSWORD","valueFrom":{"secretKeyRef":{"key":"clinic-password","name":"vet-db"}}}

$ set -a; . v2/_run/secrets.env; set +a; n=0
$ for v in "$DB_ROOT_PASSWORD" "$DB_AUTH_PASSWORD" "$DB_CLINIC_PASSWORD" "$DB_RESERVATION_PASSWORD" "$REDIS_PASSWORD"; do
    n=$((n + $(kubectl -n vet2 get deploy,sts,cm -o yaml | grep -cF "$v"))); done; echo "배포 정보에서 비밀번호 값이 나온 줄: $n"
# 출력 예
배포 정보에서 비밀번호 값이 나온 줄: 0
```

`$(DB_HOST)` 가 ConfigMap 의 값 `mysql` 로 채워져 URL 이 되었다. 비밀번호는 배포 정보에 이름(`vet-db` 의 `clinic-password`)만 있고 값은 없다. 실제 비밀번호 5개로 배포 정보 전체를 찾아도 0줄이다. 가장 단순한 배포(v0)는 같은 검사에서 16줄이 나왔다 (③ K-3).

### 3. 실행 사용자

```bash
$ for p in $(kubectl -n vet2 get pods -o name); do printf "%-40s " $p; kubectl -n vet2 exec $p -- id -u; done
# 출력 예
pod/auth-7ff9ccdc98-447t4                10001
pod/auth-7ff9ccdc98-qqchl                10001
pod/clinic-569fc777c6-77d92              10001
pod/clinic-569fc777c6-bbxbr              10001
pod/mysql-0                              999
pod/redis-596f7f8ddc-wbbw6               999
pod/reservation-b7f5779db-6fln6          10001
pod/reservation-b7f5779db-z2fbs          10001
pod/web-784b5d88dc-d748d                 82
pod/web-784b5d88dc-x9rpz                 82
```

`runAsNonRoot: true` 를 둔 Pod 는 이미지의 사용자가 root 면 시작하지 않는다. 모든 Pod 가 root 가 아닌 사용자로 돈다.

### 4. 밖에서 접속

```bash
$ curl -s -o /dev/null -w "/ %{http_code}\n" http://$W1:30080/
# 출력 예
/ 200

$ curl -s -D - -o /dev/null http://$W1:30080/api/notices | grep -iE "^HTTP|x-web-node|x-served-by"
# 출력 예
HTTP/1.1 200
X-Web-Node: web-784b5d88dc-d748d
X-Served-By: clinic-569fc777c6-bbxbr
```

응답 헤더에 요청을 처리한 **Pod 이름**이 나온다. web Pod 는 vet2-w2, clinic Pod 는 vet2-w1 에 있다. 요청은 노드를 넘어 Pod 끼리 Flannel 로 전달되었다. 브라우저로 `http://<W1 공인 IP>:30080/` 을 열 수 있다.

### 5. 시나리오 테스트

```bash
$ v2/tests/with-secrets.sh node v2/tests/scenario.mjs --base-url http://$W1:30080 --db-exec "kubectl -n vet2 exec mysql-0 --"
# 출력 예
시나리오 테스트  2026-11-25 11:32:14 KST
대상: 웹 서버 경유  http://<W1 공인 IP>:30080
...(생략)...
결과: 통과 65 / 실패 0
```

`--db-exec` 은 DB 계정 경계 검사(11번)를 `kubectl exec` 로 MySQL Pod 안에서 실행하게 한다. MySQL 은 밖에서 닿지 않기 때문이다.

### 6. DB 는 밖에서 닿지 않는다

```bash
$ timeout 5 bash -c "echo > /dev/tcp/$W1/3306" 2>/dev/null && echo "3306 열림" || echo "3306 닫힘"
# 출력 예
3306 닫힘
```

### 7. 결과 확인

| 항목 | 내용 |
|---|---|
| Probe | startup · readiness · liveness 모두 `/health` |
| 비밀번호 | 배포 정보에 0줄. Secret 이름만 |
| 사용자 | 10001, 999, 82. root 없음 |
| 접속 | NodePort 30080 으로 밖에서, 시나리오 65 / 65 |
| DB | ClusterIP. 밖에서 3306 닫힘 |

## 자원 정리

lab06 에서 그대로 쓴다. 앱만 지우려면:

```bash
$ kubectl delete namespace vet2
```

| 항목 | 내용 |
|---|---|
| Namespace `vet2` | 안의 Deployment·StatefulSet·Service·Secret·PVC 가 모두 삭제된다 |
| PV `vet2-mysql` | `Retain` 이라 남는다 (상태 `Released`). 워커1 의 `/var/lib/vet2-mysql` 에 데이터도 남는다. 다시 쓰려면 PV 를 지우고 lab04 의 `storage.yaml` 을 다시 적용한다 |

**한 번에 하기:** 1 ~ 3단계는 `v2/k8s/secrets.sh -n vet2`, `v2/k8s/kubeadm/ecr-pull-secret.sh -n vet2`, `v2/k8s/apply.sh kubeadm` 이 같은 명령을 실행한다. `apply.sh kubeadm --render` 는 적용하지 않고 렌더 결과만 보여 준다 (계정 번호와 IP 는 가려서).
