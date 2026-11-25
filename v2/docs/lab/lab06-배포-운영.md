# [실습] lab06: 배포 운영

| 속성 | 값 |
|---|---|
| 상위 항목 | ③ 쿠버네티스 전환 |
| 선행 작업 | [lab05: 앱 배포](lab05-앱-배포.md) |
| 후속 작업 | [lab07: EKS](lab07-EKS.md) |

요청을 계속 보내는 동안 Pod 를 지우고, 이미지를 업데이트하고, 롤백한다. 실패한 요청이 없는 것과 그 이유(복제본 2개, Probe, 롤링 업데이트 설정)를 확인한다. 예약을 만든 뒤 MySQL Pod 를 지워 데이터가 볼륨에 남는 것을 확인한다.

## 실습 목표

- Pod 를 지우면 ReplicaSet 이 새 Pod 를 만들고, 그동안 요청이 실패하지 않는 것을 확인한다
- `kubectl set image` 로 clinic 을 1.0.1 로 업데이트하고, 새 ReplicaSet 으로 Pod 가 하나씩 바뀌는 것을 확인한다
- `kubectl rollout undo` 로 되돌리고, 예전 ReplicaSet 이 다시 쓰이는 것을 확인한다
- 세 작업 모두에서 실패한 요청이 0건인 것을 확인한다
- MySQL Pod 를 지워도 예약이 남는 것을 확인한다

## 사전 준비

| 항목 | 내용 | 비고 |
|---|---|---|
| 클러스터 | lab05 의 앱이 떠 있는 kubeadm 클러스터 | |
| 실행 위치 | 이 PC | `KUBECONFIG=v2/_run/kubeconfig-kubeadm` |
| 이미지 | ECR 의 `vet2-clinic:1.0.1` | 같은 소스, 버전 문자열만 1.0.1 |
| Namespace | `vet2` | |
| 변수 | `W1`(워커1 공인 IP), `REG` | lab05 |
| 요청 도구 | `v2/tests/traffic.mjs` | 동시 5개로 요청을 계속 보내며 실패를 센다 |

요청은 화면이 하는 것을 돌아가며 보낸다: 소개 페이지, 상태 3개, 공지, 그리고 로그인한 보호자의 내 정보·반려동물·내 예약. 200 이 아닌 응답, 5초 안에 응답 없음, 로그인 풀림(401)을 실패로 센다.

```bash
$ tstart() { rm -f /tmp/stop; node v2/tests/traffic.mjs --base-url http://$W1:30080 --seconds 600 --stop-file /tmp/stop > /tmp/traffic.out 2>&1 & TP=$!; sleep 4; }
$ tstop()  { sleep 5; touch /tmp/stop; wait $TP; cat /tmp/traffic.out; }
```

`tstart` 는 요청을 백그라운드로 보내기 시작하고, `tstop` 은 5초 더 보낸 뒤 멈추고 결과를 출력한다. Windows 의 Git Bash 에서는 `--stop-file` 경로를 `C:/...` 형식으로 준다.

## 1. 자동 복구

### 1. Pod 삭제

```bash
$ kubectl -n vet2 get pods -l app=web -o wide
# 출력 예
NAME                   READY   STATUS    RESTARTS   AGE   IP           NODE      ...
web-784b5d88dc-d748d   1/1     Running   0          4m    10.244.2.6   vet2-w2   ...
web-784b5d88dc-x9rpz   1/1     Running   0          4m    10.244.1.8   vet2-w1   ...

$ tstart
$ kubectl -n vet2 delete pod {Pod 이름} --wait=false
# 출력 예
pod "web-784b5d88dc-d748d" deleted from vet2 namespace
```

{Pod 이름} 에는 바로 위 출력에서 web Pod 이름 하나를 입력한다.

### 2. 새 Pod

```bash
$ sleep 2; kubectl -n vet2 get pods -l app=web -o wide
# 출력 예
NAME                   READY   STATUS        RESTARTS   AGE    IP           NODE      ...
web-784b5d88dc-d748d   1/1     Terminating   0          4m6s   10.244.2.6   vet2-w2   ...
web-784b5d88dc-dfgsr   1/1     Running       0          2s     10.244.2.7   vet2-w2   ...
web-784b5d88dc-x9rpz   1/1     Running       0          4m6s   10.244.1.8   vet2-w1   ...

$ sleep 15; kubectl -n vet2 get pods -l app=web -o wide
# 출력 예
NAME                   READY   STATUS    RESTARTS   AGE     IP           NODE      ...
web-784b5d88dc-dfgsr   1/1     Running   0          18s     10.244.2.7   vet2-w2   ...
web-784b5d88dc-x9rpz   1/1     Running   0          4m22s   10.244.1.8   vet2-w1   ...

$ tstop
# 출력 예
[트래픽] 27.5초 동안 요청 1921건, 실패 0건
```

지운 Pod 가 `Terminating` 인 동안 ReplicaSet 이 새 Pod(`-dfgsr`)를 만들어 2초 만에 Running 이 되었다. 새 Pod 는 다른 IP(10.244.2.7)를 받았다. 지운 Pod 는 `preStop` 5초 동안 기다리는 사이 Service 의 요청 대상에서 먼저 빠졌고, 그동안 남은 Pod 가 요청을 받았다. 실패 0건이다.

### 3. 결과 확인

| 항목 | 내용 |
|---|---|
| Pod 삭제 | ReplicaSet 이 바로 새 Pod 를 만든다. 새 IP |
| 요청 | 약 1,900건 중 실패 0건 |

## 2. 롤링 업데이트

### 1. 현재 버전

```bash
$ curl -s http://$W1:30080/api/status/clinic; echo
# 출력 예
{"service":"clinic","status":"ok","version":"1.0.0","servedBy":"clinic-569fc777c6-bbxbr"}
```

`/api/status/clinic` 은 clinic 의 버전과 응답한 Pod 이름을 돌려준다.

### 2. 이미지 바꾸기

```bash
$ tstart
$ kubectl -n vet2 set image deploy/clinic clinic=$REG/vet2-clinic:1.0.1
# 출력 예
deployment.apps/clinic image updated

$ kubectl -n vet2 rollout status deploy/clinic --timeout=180s
# 출력 예
Waiting for deployment "clinic" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "clinic" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "clinic" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "clinic" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "clinic" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "clinic" rollout to finish: 1 old replicas are pending termination...
deployment "clinic" successfully rolled out

$ kubectl -n vet2 get rs -l app=clinic
# 출력 예
NAME                DESIRED   CURRENT   READY   AGE
clinic-569fc777c6   0         0         0       5m7s
clinic-5cbdb46bbc   2         2         2       35s
```

이미지가 바뀌자 Deployment 가 새 ReplicaSet(`5cbdb46bbc`)을 만들었다. `maxSurge: 1`, `maxUnavailable: 0` 이라 새 Pod 하나가 **준비된 뒤에** 옛 Pod 하나를 내리고, 이것을 두 번 했다. 옛 ReplicaSet 은 0 개로 줄어 남는다. 롤백에 쓰인다.

### 3. 새 버전 확인

```bash
$ sleep 3; for i in 1 2 3 4; do curl -s http://$W1:30080/api/status/clinic; echo; sleep 1; done
# 출력 예
{"service":"clinic","status":"ok","version":"1.0.1","servedBy":"clinic-5cbdb46bbc-ksq88"}
{"service":"clinic","status":"ok","version":"1.0.1","servedBy":"clinic-5cbdb46bbc-ksq88"}
{"service":"clinic","status":"ok","version":"1.0.1","servedBy":"clinic-5cbdb46bbc-6jzvc"}
{"service":"clinic","status":"ok","version":"1.0.1","servedBy":"clinic-5cbdb46bbc-6jzvc"}

$ tstop
# 출력 예
[트래픽] 52.0초 동안 요청 3615건, 실패 0건
```

새 ReplicaSet 의 Pod 두 개가 번갈아 1.0.1 로 답한다. 업데이트하는 동안 약 3,600건 중 실패는 0건이다. 이번 실행에서는 3초 뒤 물었을 때 모두 1.0.1 이었다. 다른 실행에서는 `rollout status` 가 끝난 직후 몇 초 동안 예전 버전이 답하기도 했다 (③ O-1). web(Apache)이 서비스와의 연결을 재사용해, 아직 끝나지 않은 옛 Pod 로 이어진 연결이 잠시 남기 때문으로 보인다.

### 4. 결과 확인

| 항목 | 내용 |
|---|---|
| 방식 | 새 ReplicaSet, 새 Pod 하나 준비 → 옛 Pod 하나 내림 × 2 |
| 요청 | 약 3,600건 중 실패 0건 |

## 3. 롤백

### 1. 기록과 되돌리기

```bash
$ kubectl -n vet2 rollout history deploy/clinic
# 출력 예
deployment.apps/clinic
REVISION  CHANGE-CAUSE
1         <none>
2         <none>

$ tstart
$ kubectl -n vet2 rollout undo deploy/clinic
# 출력 예
Warning: resource deployments/clinic was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/clinic rolled back

$ kubectl -n vet2 rollout status deploy/clinic --timeout=180s
# 출력 예
...(생략)...
deployment "clinic" successfully rolled out
```

`undo` 는 바로 앞 버전(REVISION 1)으로 되돌린다. 경고는 클러스터의 실제 상태가 Git 의 매니페스트(`apply` 로 적용한 것)와 어긋나게 된다는 뜻이다. 실습 뒤에는 lab05 의 렌더·적용을 다시 해서 맞춘다 (③ O-5).

### 2. 확인

```bash
$ sleep 3; for i in 1 2 3 4; do curl -s http://$W1:30080/api/status/clinic; echo; sleep 1; done
# 출력 예
{"service":"clinic","status":"ok","version":"1.0.0","servedBy":"clinic-569fc777c6-dk5f8"}
{"service":"clinic","status":"ok","version":"1.0.0","servedBy":"clinic-569fc777c6-hgvq5"}
{"service":"clinic","status":"ok","version":"1.0.0","servedBy":"clinic-569fc777c6-dk5f8"}
{"service":"clinic","status":"ok","version":"1.0.0","servedBy":"clinic-569fc777c6-hgvq5"}

$ tstop
# 출력 예
[트래픽] 47.6초 동안 요청 3319건, 실패 0건

$ kubectl -n vet2 get pods -l app=clinic -o wide
# 출력 예
NAME                          READY   STATUS    RESTARTS   AGE    IP            NODE      ...
clinic-569fc777c6-dk5f8       1/1     Running   0          44s    10.244.2.9    vet2-w2   ...
clinic-569fc777c6-hgvq5       1/1     Running   0          29s    10.244.1.11   vet2-w1   ...
```

Pod 이름의 가운데(`569fc777c6`)가 처음 ReplicaSet 의 것이다. 롤백은 새로 만드는 것이 아니라 예전 ReplicaSet 을 다시 2개로 늘리고 새 것을 0 으로 줄이는 롤링 업데이트다. 되돌린 Pod 도 두 노드에 하나씩 놓였다.

### 3. 결과 확인

| 항목 | 내용 |
|---|---|
| 방식 | 예전 ReplicaSet 을 다시 늘린다 |
| 요청 | 약 3,300건 중 실패 0건 |

같은 실험을 가장 단순한 배포(v0: 복제본 1, Probe 없음, preStop 없음)로 하면 다시 배포 중 약 300건 중 240건, 업데이트·롤백 중 약 210건 중 125건이 503 이었다 (③ K-1).

## 4. MySQL Pod 를 바꿔도 남는 데이터

### 1. 예약 만들기

```bash
$ curl -s -c /tmp/c.txt -H "Content-Type: application/json" \
    -d '{"loginId":"owner001","password":"test-only"}' http://$W1:30080/api/auth/login; echo
# 출력 예
{"userId":6,"loginId":"owner001","name":"안소율","role":"OWNER","vetId":null}

$ curl -s "http://$W1:30080/api/slots?date=2026-11-28&type=CHECKUP" | head -c 220; echo
# 출력 예
[{"slotId":162,"vetId":2,"vetName":"이도윤","vetTitle":"원장","startAt":"2026-11-28T09:30:00","visitType":"CHECKUP","isEvent":false},{"slotId":150,"vetId":1,"vetName":"김하늘","vetTitle":"대표원장","startAt":

$ curl -s -b /tmp/c.txt -H "Content-Type: application/json" -d '{"petId":1,"slotId":162}' http://$W1:30080/api/reservations; echo
# 출력 예
{"reservationId":180,"petId":1,"petName":"콩이","petSpecies":"DOG","slotId":162,"startAt":"2026-11-28T09:30:00","visitDate":"2026-11-28","visitType":"CHECKUP","vetId":2,"vetName":"이도윤","vetTitle":"원장","isEvent":false,"status":"REQUESTED","servedBy":"reservation-b7f5779db-6fln6","createdAt":"2026-11-25T11:37:20"}
```

날짜는 앞으로 2 ~ 8일 사이의 일요일이 아닌 날, `slotId` 는 앞 명령에 나온 빈 시간 하나를 넣는다. 예약 180번이 만들어졌다.

### 2. MySQL Pod 지우기

```bash
$ kubectl -n vet2 delete pod mysql-0
# 출력 예
pod "mysql-0" deleted from vet2 namespace

$ kubectl -n vet2 get pod mysql-0 -o wide
# 출력 예
NAME      READY   STATUS              RESTARTS   AGE   IP       NODE      ...
mysql-0   0/1     ContainerCreating   0          1s    <none>   vet2-w1   ...

$ kubectl -n vet2 wait --for=condition=Ready pod/mysql-0 --timeout=300s
# 출력 예
pod/mysql-0 condition met

$ kubectl -n vet2 logs mysql-0 | grep -c "\[vet\]"
# 출력 예
0
```

StatefulSet 이 같은 이름 `mysql-0` 으로 다시 만들었다. 같은 PVC(`data-mysql-0`)를 붙이므로 같은 노드(vet2-w1)의 같은 폴더를 쓴다. 초기화 로그(`[vet]`)가 0줄이다. 데이터 폴더가 비어 있지 않아 초기화를 건너뛰었다.

### 3. 예약 확인

```bash
$ curl -s -b /tmp/c.txt http://$W1:30080/api/reservations/me | grep -o '{"reservationId":180[^}]*}'
# 출력 예
{"reservationId":180,"petId":1,"petName":"콩이","petSpecies":"DOG","slotId":162,"startAt":"2026-11-28T09:30:00","visitDate":"2026-11-28","visitType":"CHECKUP","vetId":2,"vetName":"이도윤","vetTitle":"원장","isEvent":false,"status":"REQUESTED","servedBy":"reservation-b7f5779db-6fln6","createdAt":"2026-11-25T11:37:20"}

$ curl -s -o /dev/null -w "취소 %{http_code}\n" -b /tmp/c.txt -X DELETE http://$W1:30080/api/reservations/180
# 출력 예
취소 204
```

예약 180번이 그대로 있다. 확인한 뒤 시험 예약을 취소했다. MySQL 이 다시 뜨는 동안(약 10초)은 DB 를 쓰는 요청이 실패한다. DB 가 하나뿐인 구성의 한계다 (③ 6.3: 11초 동안 26건).

볼륨 없는 Deployment 로 MySQL 을 띄운 v0 에서 같은 실험을 하면, 새 Pod 가 빈 데이터 폴더로 떠서 다시 초기화하고 예약이 사라졌다 (③ K-2).

### 4. 결과 확인

| 항목 | 내용 |
|---|---|
| MySQL Pod | 같은 이름, 같은 PVC, 같은 노드로 다시 뜬다 |
| 초기화 | 건너뜀 (데이터가 있다) |
| 예약 | 그대로 남았다 |

## 자원 정리

```bash
$ rm -f /tmp/c.txt /tmp/stop /tmp/traffic.out
```

| 항목 | 내용 |
|---|---|
| 앱 | lab08 에서 쓴다. 롤백으로 생긴 Git 과의 어긋남은 lab05 의 렌더·적용으로 맞춘다 |
| 시험 예약 | 취소했다 |

**한 번에 하기:** 1 ~ 3단계와 4단계는 `v2/tests/k8s-ops.sh --base-url http://$W1:30080 -n vet2 --new-clinic-image $REG/vet2-clinic:1.0.1` 이 요청을 보내며 한 번에 실행한다 (다시 배포 포함).
