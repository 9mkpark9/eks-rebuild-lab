#!/usr/bin/env bash
# 요금이 나오는 AWS 자원이 남아 있는지 본다. 읽기만 하고 아무것도 지우지 않는다.
# 실습을 끝내고 자원을 지운 뒤, "남은 자원이 없음"을 확인하는 증거로 쓴다.
#
#   scripts/aws-leftovers.sh                  aws configure 의 리전
#   AWS_REGION=ap-northeast-2 scripts/aws-leftovers.sh
#
# 보는 것: EKS 클러스터, EC2 인스턴스, 로드밸런서, NAT 게이트웨이, 탄력적 IP, EBS 볼륨, ECR 저장소, RDS
# 남은 것이 있으면 종료 코드 1 을 돌려준다. 계정 번호는 가려서 출력한다.
set -u

REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"
[ -n "$REGION" ] || { echo '리전을 알 수 없습니다. AWS_REGION 을 지정하세요.' >&2; exit 2; }

mask() { sed -E 's/[0-9]{12}/************/g'; }
LEFT=0

# check 이름 "aws 명령 …"   결과가 비어 있으면 없음, 아니면 줄마다 출력한다
check() {
    local title="$1"; shift
    local out
    if ! out=$(aws --region "$REGION" "$@" --output text 2>&1); then
        printf '[확인 못 함] %s — %s\n' "$title" "$(printf '%s' "$out" | tr -d '\r' | tail -1 | mask)"
        LEFT=$((LEFT + 1)); return
    fi
    out=$(printf '%s' "$out" | tr -d '\r' | grep -v '^None$' | grep -v '^$' || true)
    if [ -z "$out" ]; then printf '[없음] %s\n' "$title"
    else
        printf '[남음] %s\n' "$title"
        printf '%s\n' "$out" | mask | sed 's/^/        /'
        LEFT=$((LEFT + 1))
    fi
}

echo "리전: $REGION   확인 시각: $(date -u -d "@$(( $(date +%s) + 9 * 3600 ))" '+%F %T') KST"
echo

check 'EKS 클러스터'            eks list-clusters --query 'clusters[]'
check 'EC2 인스턴스 (종료된 것 제외)' ec2 describe-instances \
      --filters 'Name=instance-state-name,Values=pending,running,stopping,stopped' \
      --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`]|[0].Value]'
check '로드밸런서 (ALB, NLB)'    elbv2 describe-load-balancers --query 'LoadBalancers[].[LoadBalancerName,Type,State.Code]'
check '로드밸런서 (Classic)'     elb describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName'
check 'NAT 게이트웨이'           ec2 describe-nat-gateways --filter 'Name=state,Values=pending,available' \
      --query 'NatGateways[].[NatGatewayId,State]'
check '탄력적 IP'                ec2 describe-addresses --query 'Addresses[].[AllocationId,PublicIp,AssociationId]'
check 'EBS 볼륨'                 ec2 describe-volumes --query 'Volumes[].[VolumeId,Size,State,VolumeType]'
check 'EBS 스냅샷 (내 것)'       ec2 describe-snapshots --owner-ids self --query 'Snapshots[].[SnapshotId,VolumeSize,StartTime]'
check 'ECR 저장소'               ecr describe-repositories --query 'repositories[].repositoryName'
check 'RDS 인스턴스'             rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus]'

echo
if [ "$LEFT" = 0 ]; then echo '결과: 남은 자원이 없다.'
else echo "결과: 확인할 항목이 ${LEFT}개 있다. 정지한 EC2 도 디스크(EBS) 요금이 나온다."; fi
[ "$LEFT" = 0 ]
