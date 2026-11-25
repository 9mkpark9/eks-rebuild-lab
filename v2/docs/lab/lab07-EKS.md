# [실습] lab07: EKS

| 속성 | 값 |
|---|---|
| 상위 항목 | ④ EKS 전환 |
| 선행 작업 | [lab05: 앱 배포](lab05-앱-배포.md) |
| 후속 작업 | [lab08: 선택 과제 RDS](lab08-선택-RDS.md) |

lab05 와 같은 앱을 EKS Auto Mode 에 올린다. 매니페스트는 같은 base 를 쓰고 overlay 만 다르다. 노드가 미리 없고 Pod 를 올릴 때 생기는 것, 밖으로는 Ingress 가 만든 ALB 로 여는 것, 볼륨은 EBS 로 받는 것을 확인한다. 클러스터에 처음부터 있는 StorageClass `gp2` 로는 볼륨이 만들어지지 않는 것을 재현한다.

## 실습 목표

- EKS Auto Mode 클러스터에 처음에는 노드가 0대인 것을 확인한다
- 기본 StorageClass `gp2` 로 요청한 볼륨이 계속 `Pending` 인 것과 그 이유를 확인한다
- 앱을 적용하면 Auto Mode 가 두 가용 영역에 노드를 만들고, 복제본이 나뉘는 것을 확인한다
- MySQL 볼륨이 EBS(gp3)로 만들어지는 것을 확인한다
- Ingress 로 만들어진 ALB 의 구성(대상, 상태 확인, 허용 주소)을 확인하고 시나리오 테스트를 통과시킨다
- ECR 로그인 Secret 없이 이미지를 받는 것을 확인한다

## 사전 준비

| 항목 | 내용 | 비고 |
|---|---|---|
| 클러스터 | EKS 1.36 Auto Mode `vet2-eks` | 스택 `vet2-eks`. 처음 만들 때 11분 안팎 (2026-11-23 에 669초) |
| 실행 위치 | 이 PC (kubectl, AWS CLI) | |
| 이미지 | ECR 의 lab05 와 같은 이미지 | |
| Namespace | `vet2` (앱), `lab07-prob` (gp2 재현) | |
| 비용 | 컨트롤 플레인 시간당 0.10달러 + 노드 c5a.large 시간당 0.086달러 × 2 + ALB 약 0.03달러 | 자원 정리 참고 |
| 변수 | `REG`, `MY_CIDR` | lab03 |

## 1. 클러스터

### 1. 스택과 클러스터

```bash
$ cf eks --parameter-overrides MyCidr=$MY_CIDR
# 출력 예

Waiting for changeset to be created..

No changes to deploy. Stack vet2-eks is up to date

$ aws eks describe-cluster --name vet2-eks --query "cluster.[name,version,status,computeConfig.enabled,storageConfig.blockStorage.enabled,kubernetesNetworkConfig.elasticLoadBalancing.enabled,computeConfig.nodePools]" --output text
# 출력 예
vet2-eks	1.36	ACTIVE	True	True	True
general-purpose	system
```

이 출력은 이미 만들어 둔 스택에 실행한 것이다. 처음이면 클러스터를 만들고 `Successfully created/updated stack` 으로 끝난다. `True True True` 는 Auto Mode 의 노드 관리, EBS 볼륨, 로드밸런서 기능이 켜져 있다는 뜻이다. 노드 풀은 `general-purpose`(앱)와 `system` 두 가지다.

[eks.yaml](../../infra/eks.yaml) 의 핵심:

| 설정 | 값 | 왜 |
|---|---|---|
| `ComputeConfig.Enabled` | true | Auto Mode. 노드를 EKS 가 만들고 고르고 정리한다 |
| `StorageConfig.BlockStorage` | true | EBS 볼륨 드라이버가 들어 있다 (따로 설치하지 않는다) |
| `KubernetesNetworkConfig.ElasticLoadBalancing` | true | Ingress 를 보고 ALB 를 만드는 기능이 들어 있다 |
| `PublicAccessCidrs` | `MyCidr` | API 서버에 이 PC 의 IP 에서만 접속 |
| 노드 IAM 역할 | `AmazonEKSWorkerNodeMinimalPolicy`, `AmazonEC2ContainerRegistryPullOnly` | 노드가 이 역할로 ECR 에서 이미지를 받는다 |

### 2. kubectl

```bash
$ aws eks update-kubeconfig --name vet2-eks --kubeconfig v2/_run/kubeconfig-eks
# 출력 예
Updated context arn:aws:eks:ap-northeast-2:************:cluster/vet2-eks in v2/_run/kubeconfig-eks

$ export KUBECONFIG=$PWD/v2/_run/kubeconfig-eks
$ kubectl get nodes
# 출력 예
No resources found
```

EKS 의 kubeconfig 에는 인증서가 아니라 "`aws eks get-token` 을 실행해 토큰을 받는다" 는 설정이 들어간다. 그래서 kubectl 을 쓸 때마다 AWS 로그인 세션이 필요하다. 노드는 0대다. 올릴 Pod 가 없으면 Auto Mode 는 노드를 만들지 않는다.

### 3. 결과 확인

| 항목 | 내용 |
|---|---|
| 클러스터 | ACTIVE, 1.36, Auto Mode |
| 노드 | 0대 (Pod 가 없으므로) |

## 2. 기본 StorageClass gp2

### 1. 클러스터에 있는 것

```bash
$ kubectl get storageclass
# 출력 예
NAME       PROVISIONER                 RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
gp2        kubernetes.io/aws-ebs       Delete          WaitForFirstConsumer   false                  41h
vet2-ebs   ebs.csi.eks.amazonaws.com   Delete          WaitForFirstConsumer   false                  20h

$ kubectl get csidrivers
# 출력 예
NAME                           ATTACHREQUIRED   PODINFOONMOUNT   STORAGECAPACITY   TOKENREQUESTS            ...
ebs.csi.eks.amazonaws.com      true             false            false             <unset>                  ...
efs.csi.aws.com                false            false            false             <unset>                  ...
spiffe.csi.eks.amazonaws.com   false            true             false             pods.eks.amazonaws.com   ...
```

`gp2` 는 클러스터를 만들 때부터 있던 것, `vet2-ebs` 는 이 작업에서 만든 것이다 (처음이면 `gp2` 만 보인다). 두 StorageClass 의 PROVISIONER 이름이 다르다. 클러스터에 있는 EBS 드라이버는 `ebs.csi.eks.amazonaws.com` 하나다.

### 2. gp2 로 볼륨 요청

① `v2/tests/prob/pvc-gp2.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data-gp2 }
spec:
  storageClassName: gp2
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 1Gi } }
---
apiVersion: v1
kind: Pod
metadata: { name: use-gp2 }
spec:
  containers:
    - name: c
      image: registry.k8s.io/pause:3.10
      volumeMounts: [{ name: d, mountPath: /data }]
  volumes: [{ name: d, persistentVolumeClaim: { claimName: data-gp2 } }]
```

```bash
$ kubectl create ns lab07-prob && kubectl -n lab07-prob apply -f v2/tests/prob/pvc-gp2.yaml
# 출력 예
namespace/lab07-prob created
persistentvolumeclaim/data-gp2 created
pod/use-gp2 created
```

60초 정도 기다린 뒤 조회한다. 노드가 있는 상태에서 해야 한다 (이 실습에서는 3단계를 마친 뒤 실행했다. 노드가 0대면 Pod 가 놓일 곳이 없어 다른 이유로 Pending 이 된다).

```bash
$ kubectl -n lab07-prob get pvc,pod
# 출력 예
NAME                             STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   ...   AGE
persistentvolumeclaim/data-gp2   Pending                                      gp2            ...   62s

NAME          READY   STATUS    RESTARTS   AGE
pod/use-gp2   0/1     Pending   0          62s

$ kubectl -n lab07-prob describe pvc data-gp2 | sed -n '/Events:/,$p'
# 출력 예
Events:
  Type    Reason                Age                From                         Message
  ----    ------                ----               ----                         -------
  Normal  WaitForFirstConsumer  64s                persistentvolume-controller  waiting for first consumer to be created before binding
  Normal  ExternalProvisioning  10s (x5 over 64s)  persistentvolume-controller  Waiting for a volume to be created either by the external provisioner 'ebs.csi.aws.com' or manually by the system admini...
```

`gp2` 의 provisioner `kubernetes.io/aws-ebs` 는 옛 이름이다. 요청은 EBS CSI 드라이버 `ebs.csi.aws.com` 으로 넘겨지는데, Auto Mode 에 들어 있는 드라이버의 이름은 `ebs.csi.eks.amazonaws.com` 이다. 기다리는 이름의 드라이버가 없어 볼륨이 영영 만들어지지 않는다 (④ E-2).

```bash
$ kubectl delete ns lab07-prob --wait=false
# 출력 예
namespace "lab07-prob" deleted
```

### 3. 결과 확인

| 항목 | 내용 |
|---|---|
| `gp2` | 옛 provisioner. 요청이 `ebs.csi.aws.com` 을 기다리며 `Pending` |
| 드라이버 | `ebs.csi.eks.amazonaws.com` 만 있다 |
| 해결 | 그 드라이버를 쓰는 StorageClass 를 직접 만든다 (3단계) |

## 3. 앱 배포

### 1. 클러스터에 한 번 넣는 것

① `v2/k8s/cluster/eks/storage.yaml`

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vet2-ebs
provisioner: ebs.csi.eks.amazonaws.com
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
parameters:
  type: gp3
  encrypted: "true"
```

| 설정 | 왜 |
|---|---|
| `provisioner: ebs.csi.eks.amazonaws.com` | Auto Mode 에 들어 있는 드라이버 |
| `WaitForFirstConsumer` | Pod 가 놓일 노드(가용 영역)가 정해진 뒤 그 영역에 볼륨을 만든다. EBS 는 한 영역 안에서만 붙는다 |
| `reclaimPolicy: Delete` | PVC 를 지우면 EBS 도 지운다. 남기면 요금이 계속 나간다 |
| `type: gp3`, `encrypted` | gp2 보다 싸고 기본 성능이 정해져 있다. 저장 데이터 암호화 |

② `v2/k8s/cluster/eks/alb.yaml`

```yaml
apiVersion: eks.amazonaws.com/v1
kind: IngressClassParams
metadata:
  name: vet2-alb
spec:
  scheme: internet-facing
---
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: vet2-alb
spec:
  controller: eks.amazonaws.com/alb
  parameters:
    apiGroup: eks.amazonaws.com
    kind: IngressClassParams
    name: vet2-alb
```

Auto Mode 에는 ALB 를 만드는 기능이 들어 있지만, 어떤 Ingress 를 맡을지 알려 주는 IngressClass 는 직접 만들어야 한다. 기본값은 VPC 안에서만 보이는 internal ALB 라서 `scheme: internet-facing` 을 적었다.

```bash
$ kubectl apply -f v2/k8s/cluster/eks/alb.yaml -f v2/k8s/cluster/eks/storage.yaml
# 출력 예
ingressclassparams.eks.amazonaws.com/vet2-alb unchanged
ingressclass.networking.k8s.io/vet2-alb unchanged
storageclass.storage.k8s.io/vet2-ebs unchanged
```

이미 넣어 두어 `unchanged` 다. 처음이면 `created` 다.

### 2. overlay (eks)

`v2/k8s/overlays/eks/kustomization.yaml` 이 kubeadm overlay 와 다른 것:

```yaml
resources:
  - namespace.yaml
  - ../../base
  - ../../mysql
  - ingress.yaml
patches:
  - target: { kind: StatefulSet, name: mysql }
    patch: |-
      - { op: add, path: /spec/volumeClaimTemplates/0/spec/storageClassName, value: vet2-ebs }
  - target: { kind: Deployment, name: web|auth|clinic|reservation }
    patch: |-
      - { op: add, path: /spec/template/spec/topologySpreadConstraints/0/minDomains, value: 2 }
      - op: add
        path: /spec/template/spec/topologySpreadConstraints/-
        value:
          maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          minDomains: 2
          matchLabelKeys: [pod-template-hash]
          labelSelector: { matchExpressions: [{ key: app, operator: Exists }] }
  - target: { kind: StatefulSet|Deployment, name: mysql|redis }
    patch: |-
      - { op: add, path: /spec/template/metadata/annotations, value: { karpenter.sh/do-not-disrupt: "true" } }
```

`v2/k8s/overlays/eks/ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  annotations:
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /health
    alb.ingress.kubernetes.io/inbound-cidrs: MY_CIDR
spec:
  ingressClassName: vet2-alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: web, port: { number: 80 } } }
```

| kubeadm (lab05) | EKS | 왜 |
|---|---|---|
| web 을 NodePort 30080 | Ingress → ALB | 노드의 보안 그룹은 Auto Mode 가 관리하고, 노드는 바뀔 때마다 IP 가 바뀐다 (④ E-1) |
| StorageClass `vet2-local` | `vet2-ebs` | 2단계 |
| `maxSkew: 1` 만 | + `minDomains: 2`, 가용 영역 분산 | Auto Mode 는 Pod 가 한 노드에 다 들어가면 노드를 줄여 몰아넣는다. `minDomains: 2` 면 노드가 2대보다 적을 때 "없는 노드에 0개" 로 세어 둘째 복제본을 같은 노드에 놓지 않고, Auto Mode 가 노드를 하나 더 만든다 (④ E-3) |
| - | MySQL·Redis 에 `do-not-disrupt` | Auto Mode 가 노드를 정리할 때 하나뿐인 MySQL·Redis 를 옮기지 않게 (④ E-4) |
| ECR 로그인 Secret | 없음 | 노드가 IAM 역할로 받는다 |

### 3. Secret 과 적용

```bash
$ set -a; . v2/_run/secrets.env; set +a
$ kubectl create namespace vet2
$ kubectl -n vet2 create secret generic vet-db \
    --from-literal=root-password="$DB_ROOT_PASSWORD" --from-literal=auth-password="$DB_AUTH_PASSWORD" \
    --from-literal=clinic-password="$DB_CLINIC_PASSWORD" --from-literal=reservation-password="$DB_RESERVATION_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
$ kubectl -n vet2 create secret generic vet-redis --from-literal=password="$REDIS_PASSWORD" --dry-run=client -o yaml | kubectl apply -f -
# 출력 예
namespace/vet2 created
secret/vet-db created
secret/vet-redis created

$ kubectl kustomize v2/k8s/overlays/eks | sed -e "s#ECR_REGISTRY#$REG#g" -e "s#MY_CIDR#$MY_CIDR#g" > v2/_run/render-eks.yaml
$ grep -E "^kind:" v2/_run/render-eks.yaml | sort | uniq -c
# 출력 예
      1 kind: ConfigMap
      5 kind: Deployment
      1 kind: Ingress
      1 kind: Namespace
      4 kind: PodDisruptionBudget
      6 kind: Service
      1 kind: StatefulSet

$ kubectl apply -f v2/_run/render-eks.yaml && rm v2/_run/render-eks.yaml
# 출력 예
...(생략)...
statefulset.apps/mysql created
...(생략)...
ingress.networking.k8s.io/web created
```

lab05 와 같은 base 에 Ingress 하나가 더해졌다. `MY_CIDR` 자리가 이번에는 Ingress 의 `inbound-cidrs` 에 채워진다.

### 4. 노드가 생기는 것

```bash
$ sleep 10; kubectl -n vet2 get pods -o wide
# 출력 예
NAME                           READY   STATUS    RESTARTS   AGE   IP       NODE     ...
auth-569ff8ff5d-dhwdb          0/1     Pending   0          13s   <none>   <none>   ...
auth-569ff8ff5d-kqzvc          0/1     Pending   0          13s   <none>   <none>   ...
...(생략)...
web-b68ff446c-vzb9b            0/1     Pending   0          13s   <none>   <none>   ...

$ kubectl get nodes
# 출력 예
No resources found

$ for d in web auth clinic reservation redis; do kubectl -n vet2 rollout status deploy/$d --timeout=600s; done
$ kubectl -n vet2 rollout status sts/mysql --timeout=600s
# 출력 예
deployment "web" successfully rolled out
deployment "auth" successfully rolled out
deployment "clinic" successfully rolled out
deployment "reservation" successfully rolled out
deployment "redis" successfully rolled out
partitioned roll out complete: 1 new pods have been updated...
```

처음에는 Pod 10개가 모두 `Pending` 이고 노드가 없다. Auto Mode 가 Pending Pod 의 요청량(CPU, 메모리)을 보고 노드를 만들었다. 적용부터 전부 준비까지 65초였다.

### 5. 결과 확인

```bash
$ kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type
# 출력 예
NAME                  STATUS   ROLES    AGE   VERSION               ZONE              INSTANCE-TYPE
i-09f2aeb2deaa6d45f   Ready    <none>   55s   v1.36.5-eks-577a51e   ap-northeast-2c   c5a.large
i-0bdb8ba1b33efee39   Ready    <none>   55s   v1.36.5-eks-577a51e   ap-northeast-2a   c5a.large

$ kubectl -n vet2 get pods -o wide
# 출력 예
NAME                           READY   STATUS    RESTARTS   AGE   IP            NODE                  ...
auth-569ff8ff5d-dhwdb          1/1     Running   0          76s   10.20.2.17    i-09f2aeb2deaa6d45f   ...
auth-569ff8ff5d-kqzvc          1/1     Running   0          76s   10.20.1.116   i-0bdb8ba1b33efee39   ...
clinic-7689464fdd-gdrzj        1/1     Running   0          76s   10.20.2.18    i-09f2aeb2deaa6d45f   ...
clinic-7689464fdd-sdw7r        1/1     Running   0          76s   10.20.1.115   i-0bdb8ba1b33efee39   ...
mysql-0                        1/1     Running   0          75s   10.20.1.117   i-0bdb8ba1b33efee39   ...
redis-69bc48d667-kdkwm         1/1     Running   0          76s   10.20.1.112   i-0bdb8ba1b33efee39   ...
reservation-6ff99569f4-6j8fk   1/1     Running   0          76s   10.20.1.113   i-0bdb8ba1b33efee39   ...
reservation-6ff99569f4-xgm42   1/1     Running   0          76s   10.20.2.16    i-09f2aeb2deaa6d45f   ...
web-b68ff446c-sc96p            1/1     Running   0          76s   10.20.2.19    i-09f2aeb2deaa6d45f   ...
web-b68ff446c-vzb9b            1/1     Running   0          76s   10.20.1.114   i-0bdb8ba1b33efee39   ...

$ kubectl -n vet2 get pvc
$ kubectl -n vet2 exec mysql-0 -- df -h /var/lib/mysql
# 출력 예
NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   ...
data-mysql-0   Bound    pvc-0c674ad4-a242-4c9e-8aa6-95a83404f9e1   2Gi        RWO            vet2-ebs       ...
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme2n1    2.0G  210M  1.7G  11% /var/lib/mysql
```

| 항목 | kubeadm (lab05) | EKS |
|---|---|---|
| 노드 | vet2-w1, vet2-w2 (미리 만듦) | 인스턴스 ID 이름, c5a.large, **2a 와 2c** (Auto Mode 가 고름) |
| Pod IP | 10.244.x.x (Flannel) | 10.20.x.x (VPC 의 실제 주소) |
| 복제본 | 두 노드에 하나씩 | 두 노드·두 영역에 하나씩 |
| MySQL 볼륨 | 워커1 의 폴더 | EBS gp3 2Gi (`/dev/nvme2n1`, 따로 붙은 디스크) |

## 4. ALB

### 1. Ingress 와 ALB

```bash
$ kubectl -n vet2 get ingress web
# 출력 예
NAME   CLASS      HOSTS   ADDRESS                                                               PORTS   AGE
web    vet2-alb   *       k8s-vet2-web-ad5f0304ae-1140755244.ap-northeast-2.elb.amazonaws.com   80      82s

$ A1=$(kubectl -n vet2 get ingress web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
$ until [ "$(curl -s -o /dev/null -m 5 -w %{http_code} http://$A1/health)" = 200 ]; do sleep 5; done
```

ADDRESS 가 ALB 의 주소다. ALB 가 만들어져 응답하기까지 2 ~ 3분이 걸린다. `until` 은 `/health` 가 200 이 될 때까지 기다린다.

```bash
$ aws elbv2 describe-load-balancers --query "LoadBalancers[?DNSName==\`$A1\`].[Scheme,Type,join(\`,\`,AvailabilityZones[].ZoneName)]" --output text
# 출력 예
internet-facing	application	ap-northeast-2c,ap-northeast-2a

$ TG=$(aws elbv2 describe-target-groups --query "TargetGroups[?starts_with(TargetGroupName,\`k8s-vet2-web\`)].TargetGroupArn" --output text)
$ aws elbv2 describe-target-health --target-group-arn $TG --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State]" --output text
# 출력 예
10.20.1.114	healthy
10.20.2.19	healthy

$ aws elbv2 describe-target-groups --target-group-arns $TG --query "TargetGroups[0].[TargetType,HealthCheckPath]" --output text
# 출력 예
ip	/health

$ LB=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?DNSName==\`$A1\`].SecurityGroups[]" --output text)
$ aws ec2 describe-security-groups --group-ids $LB --query "SecurityGroups[].IpPermissions[].[FromPort,IpRanges[].CidrIp|join(\`,\`,@)]" --output text
# 출력 예
80	<내 IP>/32
```

| 본 것 | 어디서 왔나 |
|---|---|
| `internet-facing`, 2a·2c | IngressClassParams 의 `scheme`, 서브넷의 `kubernetes.io/role/elb` 태그 |
| 대상 10.20.1.114, 10.20.2.19 (healthy) | `target-type: ip`. web Pod 두 개의 IP 로 바로 보낸다 (노드를 거치지 않는다) |
| 상태 확인 `/health` | `healthcheck-path`. readinessProbe 와 같은 경로 |
| 80 을 이 PC 의 IP 에만 | `inbound-cidrs` |

ALB 는 CloudFormation 스택이 아니라 Ingress 가 만든 것이다. 그래서 스택을 지우기 전에 Ingress(또는 Namespace)를 먼저 지워야 ALB 가 남지 않는다.

### 2. 요청과 시나리오

```bash
$ curl -s -D - -o /dev/null http://$A1/api/notices | grep -iE "^HTTP|x-web-node|x-served-by"
# 출력 예
HTTP/1.1 200
X-Web-Node: web-b68ff446c-vzb9b
X-Served-By: clinic-7689464fdd-sdw7r

$ v2/tests/with-secrets.sh node v2/tests/scenario.mjs --base-url http://$A1 --db-exec "kubectl -n vet2 exec mysql-0 --"
# 출력 예
시나리오 테스트  2026-11-25 11:45:29 KST
대상: 웹 서버 경유  http://k8s-vet2-web-ad5f0304ae-1140755244.ap-northeast-2.elb.amazonaws.com
...(생략)...
결과: 통과 65 / 실패 0
```

### 3. ECR 로그인 Secret 이 없다

```bash
$ kubectl -n vet2 get serviceaccount default -o jsonpath="{.imagePullSecrets}"; echo "(비어 있음 = ECR 로그인 Secret 없음)"
# 출력 예
(비어 있음 = ECR 로그인 Secret 없음)

$ kubectl -n vet2 get pod -l app=auth -o jsonpath="{.items[0].spec.containers[0].image}"; echo
# 출력 예
************.dkr.ecr.ap-northeast-2.amazonaws.com/vet2-auth:1.0.0
```

lab05 의 `ecr-pull` Secret 없이 ECR 이미지를 받았다. 노드의 IAM 역할(`AmazonEC2ContainerRegistryPullOnly`)로 로그인한다. 12시간 만료도 없다.

### 4. 결과 확인

| 항목 | 내용 |
|---|---|
| ALB | internet-facing, 2a·2c, 대상은 web Pod IP 2개, 80 은 이 PC 의 IP 에만 |
| 시나리오 | 통과 65 / 실패 0 |
| 이미지 | ECR 로그인 Secret 없이 |

lab06 의 운영 실험(Pod 삭제, 업데이트·롤백, MySQL Pod 교체)을 이 클러스터에서 하려면 주소만 `http://$A1` 로 바꾼다. 이 작업에서 잰 결과는 다시 배포 약 9,700건, 업데이트·롤백 약 6,700건 중 모두 실패 0건이었다 (④ 5.4).

## 자원 정리

EKS 는 노드를 멈출 수 없다. 앱을 0개로 줄이면 Auto Mode 가 노드를 없앤다.

```bash
$ kubectl -n vet2 scale deploy --all --replicas=0
$ kubectl -n vet2 scale sts mysql --replicas=0
```

| 항목 | 내용 |
|---|---|
| 노드 | 약 1분 뒤 0대. 노드 요금이 없어진다 |
| 컨트롤 플레인, ALB | 멈추는 기능이 없어 시간당 약 0.13달러가 계속 나간다 |
| EBS (MySQL) | PVC 가 남아 있어 데이터와 함께 유지 |
| 완전히 지우기 | `kubectl delete namespace vet2` (ALB 와 EBS 도 삭제) 뒤 `aws cloudformation delete-stack --stack-name vet2-eks` |

**한 번에 하기:** `v2/infra/stacks.sh up eks`, `v2/k8s/secrets.sh -n vet2`, `v2/k8s/apply.sh eks`.
