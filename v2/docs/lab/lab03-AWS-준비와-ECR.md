# [실습] lab03: AWS 준비와 ECR

| 속성 | 값 |
|---|---|
| 상위 항목 | ② 이미지 빌드·컨테이너 테스트, ③ 쿠버네티스 전환 |
| 선행 작업 | [lab02: 이미지와 compose](lab02-이미지와-compose.md) |
| 후속 작업 | [lab04: kubeadm 클러스터 구축](lab04-kubeadm-클러스터-구축.md) |

AWS 자원을 CloudFormation 스택으로 만든다. 이 실습에서는 네트워크(VPC, 서브넷, 노드 보안 그룹)와 ECR 저장소를 만들고, lab02 에서 만든 이미지를 ECR 에 올린다. 계정 번호와 이 PC 의 IP 가 문서·Git 에 남지 않게 다루는 법을 확인한다.

## 실습 목표

- AWS CLI 로그인 세션을 확인하고, 이후 명령이 쓸 변수(리전, 내 IP, ECR 주소)를 준비한다
- CloudFormation 으로 네트워크와 ECR 스택을 만들고, 스택이 내보내는 값을 확인한다
- ECR 에 로그인해 이미지를 올리고, 저장소에 태그별로 들어간 것을 확인한다

## 사전 준비

| 항목 | 내용 | 비고 |
|---|---|---|
| 실행 위치 | WSL 2 Ubuntu | lab02 의 이미지가 있는 곳 |
| 도구 | AWS CLI v2 | `aws login` 으로 로그인한다 |
| 리전 | ap-northeast-2 (서울) | |
| 비용 | 이 실습의 자원은 거의 무료 (ECR 저장량만) | EC2·EKS·RDS 는 lab04 부터 |
| 작업 디렉터리 | `~/vet2-lab` | |

## 1. 로그인과 변수

### 1. 로그인 확인

```bash
$ aws login
$ aws sts get-caller-identity --query Arn --output text
# 출력 예
arn:aws:iam::************:user/kdt8
```

`aws login` 은 브라우저로 로그인하고 몇 시간 유효한 세션을 남긴다. 세션이 끝나면 명령이 `Your session has expired` 로 실패하니 다시 로그인한다. 이 문서의 출력에서 12자리 계정 번호는 `************` 로 가렸다.

### 2. 변수

```bash
$ export AWS_REGION=ap-northeast-2 AWS_PAGER=""
$ export MY_CIDR="$(curl -s https://checkip.amazonaws.com)/32"
$ export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
$ export REG=$ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com
$ echo "MY_CIDR=$MY_CIDR"; echo "REG=$REG"
# 출력 예
MY_CIDR=<내 IP>/32
REG=************.dkr.ecr.ap-northeast-2.amazonaws.com
```

| 변수 | 쓰는 곳 |
|---|---|
| `MY_CIDR` | 보안 그룹·ALB 가 웹과 API 를 이 PC 의 IP 에만 열 때 |
| `REG` | 이미지 주소의 앞부분 (`$REG/vet2-auth:1.0.0`) |

둘 다 템플릿·매니페스트·Git 에 적지 않고, 명령을 실행할 때만 넣는다. 다른 셸을 열면 다시 export 한다.

### 3. 결과 확인

| 항목 | 내용 |
|---|---|
| 세션 | 사용자 ARN 이 나오면 로그인됨 |
| 변수 | 이 셸에만 있다 |

## 2. 스택 만들기

### 1. 템플릿 검사

```bash
$ aws cloudformation validate-template --template-body file://v2/infra/network.yaml \
    --query "[Description, Parameters[].ParameterKey]" --output text
# 출력 예
vet2 network (VPC, 2 public subnets, kubeadm node security group)
MyCidr
```

문법만 검사하고 아무것도 만들지 않는다. 이 템플릿은 매개변수 `MyCidr` 하나를 받는다.

### 2. 스택 배포 함수

```bash
$ cf() { aws cloudformation deploy --stack-name vet2-$1 --template-file v2/infra/$1.yaml \
         --capabilities CAPABILITY_NAMED_IAM --tags Project=vet2 --no-fail-on-empty-changeset "${@:2}"; }
```

| 옵션 | 왜 |
|---|---|
| `--stack-name vet2-<이름>` | 스택 이름. 템플릿 파일 이름과 맞춘다 (`network` → `v2/infra/network.yaml`) |
| `--capabilities CAPABILITY_NAMED_IAM` | IAM 역할에 이름을 붙여 만드는 템플릿(kubeadm, eks)에 필요하다 |
| `--tags Project=vet2` | 스택이 만드는 모든 자원에 태그. 같은 계정의 다른 자원과 섞이지 않고, 정리 뒤 남은 것을 태그로 찾는다 |
| `--no-fail-on-empty-changeset` | 바뀐 것이 없으면 실패가 아니라 "그대로" 로 끝낸다 |

### 3. 네트워크와 ECR

```bash
$ cf network --parameter-overrides MyCidr=$MY_CIDR
# 출력 예

Waiting for changeset to be created..

No changes to deploy. Stack vet2-network is up to date

$ cf ecr
# 출력 예

Waiting for changeset to be created..

No changes to deploy. Stack vet2-ecr is up to date
```

`deploy` 는 바뀐 것만 고친다. 이번에는 두 스택이 이미 있고 바뀐 것이 없어 그대로 끝났다. 처음 실행하면 자원을 만들고 `Successfully created/updated stack` 으로 끝난다 (lab04 의 kubeadm 스택 출력). 이 PC 의 공인 IP 가 바뀌었을 때도 같은 명령을 다시 실행하면 보안 그룹의 허용 주소만 고쳐진다.

### 4. 스택 확인

```bash
$ aws cloudformation describe-stacks --query "Stacks[?starts_with(StackName,\`vet2-\`)].[StackName,StackStatus]" --output table
# 출력 예
-------------------------------------
|          DescribeStacks           |
+---------------+-------------------+
|  vet2-rds     |  CREATE_COMPLETE  |
|  vet2-eks     |  UPDATE_COMPLETE  |
|  vet2-kubeadm |  CREATE_COMPLETE  |
|  vet2-ecr     |  CREATE_COMPLETE  |
|  vet2-network |  UPDATE_COMPLETE  |
+---------------+-------------------+

$ aws cloudformation describe-stacks --stack-name vet2-network --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output table
# 출력 예
------------------------------------------------
|                DescribeStacks                |
+-----------------+----------------------------+
|  SubnetA        |  subnet-0aef2ce080391e1b2  |
|  PrivateSubnetA |  subnet-02c76448619a44f05  |
|  SubnetC        |  subnet-05796ad33d86599bb  |
|  PrivateSubnetC |  subnet-021ec2238b7e84635  |
|  VpcId          |  vpc-08decb7473c1a02d2     |
|  NodeSgId       |  sg-05869afafce37edeb      |
+-----------------+----------------------------+
```

이 출력은 다섯 스택을 모두 만든 뒤의 것이다. 처음에는 `vet2-network`, `vet2-ecr` 둘만 있다.

network 스택은 서브넷과 보안 그룹의 ID 를 **내보낸다**(Outputs, Export). kubeadm·eks·rds 스택이 이 값을 받아 쓴다. 그래서 만드는 순서가 정해진다: `network → ecr → kubeadm, eks → rds`. 받아 쓰는 스택이 남아 있으면 내보낸 스택은 지워지지 않는다. 지우는 순서를 잘못하면 AWS 가 막아 준다.

| 스택 | 만드는 것 |
|---|---|
| `vet2-network` | VPC 10.20.0.0/16, 퍼블릭 서브넷 2(2a, 2c), 프라이빗 서브넷 2(RDS 용), 인터넷 게이트웨이, 노드 보안 그룹 |
| `vet2-ecr` | 저장소 5개 (auth, clinic, reservation, web, db). 스택을 지우면 이미지도 함께 지워진다 |

### 5. 결과 확인

| 항목 | 내용 |
|---|---|
| 스택 | `vet2-network`, `vet2-ecr` |
| 내보내는 값 | 서브넷 4개, VPC, 노드 보안 그룹 |
| 태그 | 모든 자원에 `Project=vet2` |

## 3. 이미지 올리기

### 1. ECR 로그인

```bash
$ aws ecr get-login-password | docker login --username AWS --password-stdin $REG
# 출력 예

WARNING! Your credentials are stored unencrypted in '/home/junseo/.docker/config.json'.
Configure a credential helper to remove this warning. See
https://docs.docker.com/go/credential-store/

Login Succeeded
```

로그인 비밀번호를 명령줄이 아닌 표준 입력(`--password-stdin`)으로 넘긴다. 이 비밀번호는 12시간 유효하다. 경고처럼 로그인 정보가 `~/.docker/config.json` 에 남으므로 끝나면 `docker logout` 한다.

### 2. 태그와 push

```bash
$ for i in auth:1.0.0 web:1.0.0; do docker tag vet2-$i $REG/vet2-$i && docker push $REG/vet2-$i; done
# 출력 예
...(생략)...
7c3a5aabfc1c: Layer already exists
ba02b13148ab: Pushed
1.0.0: digest: sha256:297d93a20b38cae13cebce93f8f13de4ac4269db9a8bf1aced97e993bdad6767 size: 856
...(생략)...
ecf37066e1be: Layer already exists
1f713c4def51: Pushed
1.0.0: digest: sha256:b5ee15e0e48d6a2a765be93c0502ae86490837a29b1efec87636b8e00615b0c2 size: 856
```

이미지 이름 앞에 ECR 주소를 붙인 태그를 만들고 올린다. 이미 올라가 있는 층(JRE 등)은 `Layer already exists` 로 건너뛰고, 바뀐 층만 `Pushed` 된다. 이번에는 lab01 에서 jar 를 다시 빌드했기 때문에 소스가 같아도 jar 층이 새로 올라갔다.

전체를 올릴 때는 목록을 늘린다. 이후 실습에 필요한 것은 아래 7개다.

```bash
$ for i in auth:1.0.0 clinic:1.0.0 clinic:1.0.1 reservation:1.0.0 web:1.0.0 db:1.0.0 db:1.1.0; do
    docker tag vet2-$i $REG/vet2-$i && docker push -q $REG/vet2-$i; done
```

`clinic:1.0.1` 은 lab06 의 업데이트·롤백용(같은 소스, 버전 문자열만 다름), `db:1.1.0` 은 lab08 의 RDS 초기화 Job 용이다.

### 3. 저장소 확인

```bash
$ aws ecr describe-images --repository-name vet2-auth \
    --query "sort_by(imageDetails,&imagePushedAt)[].[join(\`,\`,imageTags || \`[\"(태그 없음)\"]\`),imagePushedAt,imageSizeInBytes]" --output table
# 출력 예
------------------------------------------------------------------
|                         DescribeImages                         |
+-------------+------------------------------------+-------------+
|  (태그 없음)|  2026-11-23T18:03:47.394000+09:00  |  2104       |
...(생략)...
|  1.0.0-wsl  |  2026-11-25T07:51:27.444000+09:00  |  110299666  |
|  (태그 없음)|  2026-11-25T11:18:56.187000+09:00  |  2155       |
|  1.0.0      |  2026-11-25T11:18:56.482000+09:00  |  110299666  |
+-------------+------------------------------------+-------------+

$ docker logout $REG
# 출력 예
Removing login credentials for ************.dkr.ecr.ap-northeast-2.amazonaws.com
```

`1.0.0` 이 방금 올린 것이다. ECR 에 저장된 크기(110MB)는 압축된 크기라 `docker image ls` 의 366MB 보다 작다. 같은 태그로 다시 올리면 태그는 새 이미지로 옮겨 가고, 예전 이미지는 "태그 없음" 으로 남는다. 2KB 안팎의 "태그 없음" 항목은 이미지 본체가 아니라 BuildKit 이 함께 올린 부가 정보로 보인다 (확인하지 않음).

### 4. 결과 확인

| 항목 | 내용 |
|---|---|
| 로그인 | 12시간 유효. 끝나면 logout |
| 이미지 | `$REG/vet2-<이름>:<태그>` 로 저장소마다 |
| 다시 올리면 | 바뀐 층만 올라가고 태그가 옮겨 간다 |

## 자원 정리

이 실습의 자원은 lab04 이후에도 쓰므로 지우지 않는다. 모든 실습이 끝난 뒤 지우는 순서는 [lab08 의 자원 정리](lab08-선택-RDS.md#자원-정리)에 있다. 스택만 지운다면:

```bash
$ aws cloudformation delete-stack --stack-name vet2-ecr && aws cloudformation wait stack-delete-complete --stack-name vet2-ecr
$ aws cloudformation delete-stack --stack-name vet2-network && aws cloudformation wait stack-delete-complete --stack-name vet2-network
```

| 항목 | 내용 |
|---|---|
| `vet2-ecr` | 저장소와 그 안의 이미지가 모두 삭제된다 |
| `vet2-network` | kubeadm·eks·rds 스택이 남아 있으면 지워지지 않는다 |

**한 번에 하기:** `v2/infra/stacks.sh up network`, `stacks.sh up ecr`, `v2/infra/push-images.sh` 가 같은 명령을 실행한다.
