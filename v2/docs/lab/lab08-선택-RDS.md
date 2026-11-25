# [실습] lab08: 선택 과제 RDS

| 속성 | 값 |
|---|---|
| 상위 항목 | ⑥ 선택 과제 |
| 선행 작업 | [lab05: 앱 배포](lab05-앱-배포.md), [lab07: EKS](lab07-EKS.md) |
| 후속 작업 | 없음 (자원 정리) |

같은 앱을 Namespace `vet2-rds` 에 하나 더 띄우고 DB 만 RDS 로 바꾼다. 필수 구성(`vet2`, 클러스터 안 MySQL)은 그대로 둔다. RDS 는 사설 서브넷에 있고 두 클러스터의 노드에서만 닿는다. 빈 RDS 는 쿠버네티스 Job 이 한 번 초기화한다. kubeadm 과 EKS 두 클러스터가 RDS 하나를 함께 쓰는 것을 확인한다.

## 실습 목표

- RDS 가 사설 서브넷에 있고, 인터넷 경로가 없으며, 두 클러스터의 노드 보안 그룹에서만 3306 을 받는 것을 확인한다
- RDS 관리자 비밀번호를 Secrets Manager 에서 읽어 화면에 내지 않고 Secret 으로 넣는다
- 초기화 Job 이 RDS 에 스키마·시드·계정을 넣고, 이미 초기화된 DB 에는 아무것도 하지 않는 것을 확인한다
- 두 클러스터에서 RDS 구성으로 시나리오 테스트(65개 항목)를 통과시킨다
- RDS 의 연결 한도(60)와 서비스별 연결 수를 확인한다

## 사전 준비

| 항목 | 내용 | 비고 |
|---|---|---|
| 클러스터 | lab05 의 kubeadm, lab07 의 EKS | |
| RDS | 스택 `vet2-rds`: MySQL 8.4, db.t4g.micro, 단일 AZ, gp3 20GB 암호화 | 만들기 10분 안팎. eks 스택이 먼저 있어야 한다 |
| 실행 위치 | 이 PC | |
| Namespace | `vet2-rds` (두 클러스터 모두) | |
| 포트 | kubeadm 은 NodePort 30081, EKS 는 두 번째 ALB | |
| 비용 | RDS 시간당 0.025달러 + 저장 공간, ALB 하나 더 | |
| 변수 | `REG`, `MY_CIDR`, `W1` | lab03, lab05 |

```bash
$ cf rds
$ rout() { aws cloudformation describe-stacks --stack-name vet2-rds --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
$ RDS_HOST=$(rout Endpoint); ADMIN_ARN=$(rout AdminSecretArn)
$ jv() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(String(JSON.parse(s)[process.argv[1]])))' "$1"; }
```

`jv` 는 JSON 에서 값 하나를 꺼내는 함수다 (`jq -r .<키>` 와 같다). RDS 주소의 가운데(인스턴스마다 다른 부분)는 이 문서에서 `<id>` 로 가렸다.

## 1. RDS 구성

### 1. 인스턴스와 네트워크

```bash
$ aws rds describe-db-instances --db-instance-identifier vet2-db --query "DBInstances[0].[DBInstanceStatus,Engine,EngineVersion,DBInstanceClass,MultiAZ,PubliclyAccessible,StorageType,StorageEncrypted,AvailabilityZone,DBSubnetGroup.DBSubnetGroupName]" --output text
# 출력 예
available	mysql	8.4.11	db.t4g.micro	False	False	gp3	True	ap-northeast-2c	vet2-db-private

$ aws ec2 describe-route-tables --filters Name=tag:Name,Values=vet2-private-rt --query "RouteTables[0].Routes[].[DestinationCidrBlock,GatewayId]" --output text
# 출력 예
10.20.0.0/16	local

$ aws ec2 describe-security-groups --filters Name=group-name,Values=vet2-db --query "SecurityGroups[0].IpPermissions[].[IpProtocol,FromPort,UserIdGroupPairs[].Description|join(\`,\`,@)]" --output text
# 출력 예
tcp	3306	kubeadm-nodes,eks-auto-mode-nodes
```

| 항목 | 값 | 왜 |
|---|---|---|
| 공개 접속 | `False` | 공인 IP 가 없다 |
| 서브넷 그룹 | `vet2-db-private` (2a, 2c 의 사설 서브넷) | 라우팅 표의 경로가 VPC 안(`local`) 하나뿐이라 인터넷과 오갈 길이 없다. 설정 하나가 바뀌어도 밖에서 닿지 않는다 |
| 보안 그룹 | 3306 을 두 그룹에서만: kubeadm 노드, EKS 클러스터(Auto Mode 노드) | 두 클러스터의 Pod 만 닿는다 |
| Multi-AZ | `False` | 실습 비용. 2c 영역이 통째로 죽으면 DB 도 멈춘다 (한계) |

### 2. 관리자 비밀번호

```bash
$ echo "RDS_HOST=$RDS_HOST"
# 출력 예
RDS_HOST=vet2-db.<id>.ap-northeast-2.rds.amazonaws.com

$ aws secretsmanager describe-secret --secret-id "$ADMIN_ARN" --query "[RotationEnabled,RotationRules.AutomaticallyAfterDays]" --output text
# 출력 예
True	7

$ aws secretsmanager get-secret-value --secret-id "$ADMIN_ARN" --query SecretString --output text \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(Object.keys(JSON.parse(s)).join(" ")))'
# 출력 예
username password
```

관리자 비밀번호는 RDS 가 만들어 Secrets Manager 에 두었다 (템플릿의 `ManageMasterUserPassword: true`). 템플릿·명령줄·스택 기록 어디에도 값이 없다. 7일마다 자동으로 바뀐다. 마지막 명령은 값이 아니라 키 이름만 보여 준다.

### 3. 결과 확인

| 항목 | 내용 |
|---|---|
| 위치 | 사설 서브넷, 공인 IP 없음 |
| 접근 | 두 클러스터 노드의 보안 그룹에서 3306 만 |
| 관리자 비밀번호 | Secrets Manager, 7일마다 교체 |

## 2. kubeadm 쪽

### 1. Secret

```bash
$ set -a; . v2/_run/secrets.env; set +a
$ export KUBECONFIG=$PWD/v2/_run/kubeconfig-kubeadm
$ kubectl create namespace vet2-rds
```

`vet-db`, `vet-redis`, `ecr-pull` 은 lab05 의 1단계 명령을 `-n vet2-rds` 로 그대로 실행한다.

```bash
# 출력 예
namespace/vet2-rds created
secret/vet-db created
secret/vet-redis created
secret/ecr-pull created
serviceaccount/default patched
```

RDS 관리자 Secret:

```bash
$ J=$(aws secretsmanager get-secret-value --secret-id "$ADMIN_ARN" --query SecretString --output text)
$ kubectl -n vet2-rds create secret generic vet-rds-admin \
    --from-literal=username="$(printf %s "$J" | jv username)" \
    --from-literal=password="$(printf %s "$J" | jv password)" \
    --dry-run=client -o yaml | kubectl apply -f -
# 출력 예
secret/vet-rds-admin created
$ unset J
```

이 Secret 은 초기화 Job 만 쓴다. 앱은 lab05 와 같은 서비스 계정(`vet-db`)으로 RDS 에 접속한다. 관리자 비밀번호가 7일 뒤 바뀌면 이 Secret 은 예전 값으로 남는다. Job 을 다시 돌리기 전에 이 명령을 다시 실행한다. 앱은 영향이 없다.

### 2. overlay (kubeadm-rds)

```bash
$ kubectl kustomize v2/k8s/overlays/kubeadm-rds \
    | sed -e "s#ECR_REGISTRY#$REG#g" -e "s#MY_CIDR#$MY_CIDR#g" -e "s#RDS_HOST#$RDS_HOST#g" > v2/_run/render-krds.yaml
$ grep -E "^kind:" v2/_run/render-krds.yaml | sort | uniq -c
# 출력 예
      1 kind: ConfigMap
      5 kind: Deployment
      1 kind: Job
      1 kind: Namespace
      4 kind: PodDisruptionBudget
      5 kind: Service

$ grep -E "DB_HOST|DB_POOL_MAX|nodePort" v2/_run/render-krds.yaml
# 출력 예
  DB_HOST: vet2-db.<id>.ap-northeast-2.rds.amazonaws.com
  DB_POOL_MAX: "3"
    nodePort: 30081
          value: jdbc:mysql://$(DB_HOST):3306/vet_auth?connectionTimeZone=LOCAL&characterEncoding=UTF-8
          value: jdbc:mysql://$(DB_HOST):3306/vet_clinic?connectionTimeZone=LOCAL&characterEncoding=UTF-8
          value: jdbc:mysql://$(DB_HOST):3306/vet_reservation?connectionTimeZone=LOCAL&characterEncoding=UTF-8
              key: DB_HOST
```

lab05 와 비교하면 StatefulSet(MySQL)이 없고 Job 이 하나 있다. 바뀐 것은 ConfigMap 의 두 값과 포트뿐이다. 앱의 매니페스트(base)는 그대로다.

`v2/k8s/components/rds/kustomization.yaml` (kubeadm-rds, eks-rds 가 함께 쓰는 조각):

```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
resources:
  - db-init.yaml
configMapGenerator:
  - name: vet-config
    behavior: merge
    literals:
      - DB_HOST=RDS_HOST
      - DB_POOL_MAX=3
```

| 값 | 왜 |
|---|---|
| `DB_HOST=RDS_HOST` | 적용할 때 RDS 주소로 채운다 |
| `DB_POOL_MAX=3` | db.t4g.micro 의 연결 한도는 60 이다. 서비스 3개 × 복제본 2 × 3 = 18, 두 클러스터면 36. 배포 중 Pod 가 하나씩 더 떠도 한도 안 (⑥ R-3) |
| `db-init.yaml` | 빈 RDS 를 초기화하는 Job |

### 3. 적용과 초기화 Job

```bash
$ kubectl apply -f v2/_run/render-krds.yaml && rm v2/_run/render-krds.yaml
# 출력 예
...(생략)...
deployment.apps/web created
...(생략)...
job.batch/db-init created

$ kubectl -n vet2-rds wait --for=condition=complete job/db-init --timeout=300s && kubectl -n vet2-rds logs job/db-init
# 출력 예
job.batch/db-init condition met
[vet] 0) vet2-db.<id>.ap-northeast-2.rds.amazonaws.com 에 접속되는지 확인 (최대 5분)
[vet] 이미 초기화된 DB 입니다. 아무것도 하지 않습니다.
```

Job 은 lab02 의 db 이미지(`vet2-db:1.1.0`)에 든 같은 초기화 스크립트를 RDS 를 향해 실행한다. 이 RDS 는 앞서 초기화되어 있어 "이미 초기화된 DB" 로 끝났다. 빈 RDS 에서는 lab02 의 MySQL 로그처럼 다음이 나온다 (2026-11-24 기록, 이번에는 실행하지 않음):

```
[vet] 1) 스키마 4개와 서비스 계정 3개
[vet] 2) 테이블과 시드 (vet_load)
[vet] 3) 서비스별 스키마로 옮기고 권한 주기
[vet] 초기화 끝
```

Job 은 다시 실행되어도 안전하다. 마지막 단계(권한)까지 끝났으면 아무것도 하지 않고, 중간에 멈춘 DB 면 이어 하지 않고 실패한다. 두 클러스터가 같은 RDS 를 쓰므로 두 번째 클러스터의 Job 은 늘 "이미 초기화된 DB" 다.

### 4. 확인

```bash
$ kubectl -n vet2-rds get pods -o wide
# 출력 예
NAME                          READY   STATUS      RESTARTS   AGE   IP            NODE      ...
auth-757ffdc57c-8mjnr         1/1     Running     0          40s   10.244.2.10   vet2-w2   ...
auth-757ffdc57c-lmzm5         1/1     Running     0          40s   10.244.1.13   vet2-w1   ...
clinic-64f8f45ff-pz9c6        1/1     Running     0          40s   10.244.2.11   vet2-w2   ...
clinic-64f8f45ff-qfldc        1/1     Running     0          40s   10.244.1.14   vet2-w1   ...
db-init-kwc2s                 0/1     Completed   0          39s   10.244.2.15   vet2-w2   ...
redis-596f7f8ddc-wqvqt        1/1     Running     0          40s   10.244.2.14   vet2-w2   ...
reservation-69bdbcbb5-ccl9b   1/1     Running     0          40s   10.244.2.12   vet2-w2   ...
reservation-69bdbcbb5-h7t2s   1/1     Running     0          40s   10.244.1.15   vet2-w1   ...
web-784b5d88dc-5xbw2          1/1     Running     0          40s   10.244.2.13   vet2-w2   ...
web-784b5d88dc-jnbr4          1/1     Running     0          40s   10.244.1.16   vet2-w1   ...

$ v2/tests/with-secrets.sh bash v2/tests/rds-check.sh http://$W1:30081
# 출력 예
시나리오 테스트  2026-11-25 11:53:49 KST
대상: 웹 서버 경유  http://<W1 공인 IP>:30081
...(생략)...
결과: 통과 65 / 실패 0
```

`rds-check.sh` 는 시나리오 테스트를 실행하면서, DB 계정 경계 검사(11번)를 클러스터 안에 잠깐 띄운 mysql 클라이언트 Pod 에서 서비스 계정으로 RDS 에 접속해 한다. RDS 는 밖에서 닿지 않기 때문이다.

### 5. 결과 확인

| 항목 | 내용 |
|---|---|
| Pod | MySQL 없이 앱만. Job 은 `Completed` |
| DB | RDS (`DB_HOST`), 연결 수 3 |
| 시나리오 | 통과 65 / 실패 0 (NodePort 30081) |

## 3. EKS 쪽

### 1. Secret 과 적용

```bash
$ export KUBECONFIG=$PWD/v2/_run/kubeconfig-eks
$ kubectl create namespace vet2-rds
```

`vet-db`, `vet-redis` 는 lab07 의 명령을, `vet-rds-admin` 은 2단계의 명령을 `-n vet2-rds` 로 실행한다. ECR 로그인 Secret 은 필요 없다.

```bash
$ kubectl kustomize v2/k8s/overlays/eks-rds \
    | sed -e "s#ECR_REGISTRY#$REG#g" -e "s#MY_CIDR#$MY_CIDR#g" -e "s#RDS_HOST#$RDS_HOST#g" | kubectl apply -f -
# 출력 예
...(생략)...
job.batch/db-init created
ingress.networking.k8s.io/web created

$ kubectl -n vet2-rds wait --for=condition=complete job/db-init --timeout=300s && kubectl -n vet2-rds logs job/db-init
# 출력 예
job.batch/db-init condition met
[vet] 0) vet2-db.<id>.ap-northeast-2.rds.amazonaws.com 에 접속되는지 확인 (최대 5분)
[vet] 이미 초기화된 DB 입니다. 아무것도 하지 않습니다.
```

EKS 의 Pod 는 VPC 의 IP 를 쓰지만 노드의 네트워크 장치로 나가므로, RDS 보안 그룹이 허용한 EKS 클러스터 보안 그룹으로 RDS 에 닿았다.

### 2. 두 번째 ALB 와 시나리오

```bash
$ A2=$(kubectl -n vet2-rds get ingress web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
$ until [ "$(curl -s -o /dev/null -m 5 -w %{http_code} http://$A2/health)" = 200 ]; do sleep 10; done

$ v2/tests/with-secrets.sh bash v2/tests/rds-check.sh http://$A2
# 출력 예
시나리오 테스트  2026-11-25 11:58:31 KST
대상: 웹 서버 경유  http://k8s-vet2rds-web-5870850c38-395422364.ap-northeast-2.elb.amazonaws.com
...(생략)...
결과: 통과 65 / 실패 0
```

새 ALB 주소는 만들어진 직후 이 PC 에서 이름을 찾지 못할 수 있다. 이번 실습에서는 `curl` 이 200 을 받은 직후 시나리오를 실행하자 모든 항목이 `ENOTFOUND` 로 실패했고, 1분 뒤 다시 실행하자 65 / 65 였다. 주소가 DNS 에 퍼지는 동안 생기는 일이다.

### 3. RDS 의 연결 수

```bash
$ NS=vet2-rds bash v2/tests/rds-sql.sh "SELECT @@max_connections max_conn; SELECT user, COUNT(*) conns FROM information_schema.processlist GROUP BY user ORDER BY 2 DESC"
# 출력 예
+----------+
| max_conn |
+----------+
|       60 |
+----------+
+-----------------+-------+
| user            | conns |
+-----------------+-------+
| vet_clinic      |    12 |
| vet_auth        |     6 |
| vet_reservation |     6 |
| rdsadmin        |     2 |
| admin           |     1 |
| event_scheduler |     1 |
+-----------------+-------+
```

`rds-sql.sh` 는 클러스터 안에 mysql 클라이언트 Pod 를 잠깐 띄워 관리자로 SQL 을 실행한다. 비밀번호는 Pod 가 Secret 에서 직접 읽는다.

| 사용자 | 연결 | 계산 |
|---|---|---|
| `vet_auth`, `vet_reservation` | 6 | 두 클러스터 × 복제본 2 × 3 = 12 가 기대값이다 |
| `vet_clinic` | 12 | 두 클러스터 × 복제본 2 × 3 = 12 |

clinic 은 기대값과 같다. auth·reservation 이 6 인 것은 이 측정에서 원인을 확인하지 못했다. 연결 풀은 최소 개수를 최대와 같게 두므로 늘 3개씩 열려 있어야 한다. 합계 30 은 한도 60 의 절반이다.

### 4. 결과 확인

| 항목 | 내용 |
|---|---|
| EKS RDS 구성 | 두 번째 ALB, 시나리오 65 / 65 |
| RDS 연결 | 한도 60 중 앱 24, 관리 4 |
| 두 클러스터 | RDS 하나를 함께 쓴다. 한쪽에서 만든 예약이 다른 쪽에도 보인다 |

DB 가 있는 워커를 강제로 멈췄을 때, 같은 시간에 클러스터 안 MySQL 구성은 약 1,000건 중 372건, RDS 구성은 약 13,800건 중 39건이 실패했다 (⑥ 2.7, 2026-11-25). RDS 를 다시 시작하는 동안에는 RDS 구성도 약 20초 동안 DB 요청이 실패한다.

## 자원 정리

### 1. 멈추기 (다음에 이어서)

```bash
$ aws ec2 stop-instances --instance-ids $CP $W1ID $W2ID                       # kubeadm
$ aws rds stop-db-instance --db-instance-identifier vet2-db                    # 7일 뒤 저절로 다시 켜진다
$ export KUBECONFIG=$PWD/v2/_run/kubeconfig-eks
$ for ns in vet2 vet2-rds; do kubectl -n $ns scale deploy --all --replicas=0; done
$ kubectl -n vet2 scale sts mysql --replicas=0                                 # EKS 노드가 사라진다
```

| 항목 | 남는 요금 |
|---|---|
| kubeadm EC2 | 디스크만 |
| RDS | 저장 공간만 |
| EKS 노드 | 없음 |
| EKS 컨트롤 플레인, ALB 2개 | 시간당 약 0.16달러 (멈출 수 없다) |

### 2. 모두 지우기 (되돌릴 수 없다)

만든 순서의 거꾸로 지운다. 받는 스택이 남아 있으면 내보낸 스택은 지워지지 않는다.

```bash
$ del() { aws cloudformation delete-stack --stack-name vet2-$1 && aws cloudformation wait stack-delete-complete --stack-name vet2-$1; }
$ del rds
$ KUBECONFIG=$PWD/v2/_run/kubeconfig-eks kubectl delete namespace vet2 vet2-rds --wait=true --timeout=10m
$ del eks
$ del kubeadm
$ del ecr
$ del network
$ aws cloudformation describe-stacks --query 'Stacks[?starts_with(StackName,`vet2-`)].StackName'
$ aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=vet2 --query 'ResourceTagMappingList[].ResourceARN'
```

| 순서 | 왜 |
|---|---|
| rds 먼저 | eks·network 스택이 내보낸 보안 그룹을 쓴다 |
| EKS 안의 Namespace 를 eks 스택보다 먼저 | ALB 2개와 MySQL 의 EBS 는 Ingress·PVC 가 만든 것이라 스택에 없다. 클러스터를 먼저 지우면 지워 줄 주체가 사라져 남는다 |
| network 마지막 | kubeadm·eks 가 그 서브넷을 쓴다 |

마지막 두 명령의 결과가 비어 있어야 한다. RDS 는 지울 때 스냅샷을 남기지 않는다 (데이터가 모두 시험용이다).

**한 번에 하기:** `v2/infra/stacks.sh up rds`, 클러스터마다 `v2/k8s/secrets.sh -n vet2-rds`, `v2/k8s/rds-secret.sh -n vet2-rds`, (kubeadm 만) `v2/k8s/kubeadm/ecr-pull-secret.sh -n vet2-rds`, `v2/k8s/apply.sh kubeadm-rds` 또는 `eks-rds`. 지우기는 `v2/infra/stacks.sh down all`.
