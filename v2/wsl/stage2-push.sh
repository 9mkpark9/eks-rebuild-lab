#!/usr/bin/env bash
# ② 이미지 배포: WSL 2 에서 빌드한 이미지에 태그를 붙여 ECR 에 올린다.
# 클러스터가 쓰는 1.0.0 태그를 덮어쓰지 않도록 1.0.0-wsl 태그로 올린다.
set -u
SRC=/mnt/c/Users/junseo/Desktop/webserver/eks-rebuild-lab
export CAP_DIR="$SRC/v2/_run/capture" AWS_PAGER=""
cd "$HOME/vet2-lab"; . v2/tests/cap.sh
REGION=ap-northeast-2
REG="$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$REGION.amazonaws.com"
cap w2-09-login "② ECR 로그인 (WSL 2)" bash -c "aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REG 2>&1 | grep -v WARNING"
push() {
    for s in auth clinic reservation web; do
        docker tag vet2-$s:1.0.0 $REG/vet2-$s:1.0.0-wsl
        echo "\$ docker push $REG/vet2-$s:1.0.0-wsl"
        docker push $REG/vet2-$s:1.0.0-wsl 2>&1 | grep -E 'digest|Pushed|exists' | tail -2
    done
}
cap w2-10-push "② 태그를 붙여 ECR 에 push (1.0.0-wsl)" push
cap w2-11-ecr "② ECR 에 올라간 이미지와 플랫폼" bash -c "for s in auth clinic reservation web; do aws ecr describe-images --region $REGION --repository-name vet2-\$s --image-ids imageTag=1.0.0-wsl --query 'imageDetails[0].[repositoryName,join(\`,\`,imageTags),imagePushedAt,imageSizeInBytes]' --output text; docker buildx imagetools inspect $REG/vet2-\$s:1.0.0-wsl | grep -m1 Platform; done"
