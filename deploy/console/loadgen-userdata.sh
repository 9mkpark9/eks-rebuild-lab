#!/bin/bash
# Locust EC2 사용자 데이터 — 콘솔용 (docs/07 8-5). 내용은 cfn/loadgen.yaml 과 같다.
# ▼ 내 값으로 바꾼다
ARTIFACT_BUCKET="vet01-artifacts-<계정ID 12자리>"
# ▲
dnf install -y python3-pip
pip3 install "locust>=2.30,<3"
mkdir -p /opt/loadtest/results
aws s3 cp "s3://$ARTIFACT_BUCKET/loadgen/locustfile.py" /opt/loadtest/locustfile.py --region ap-northeast-2
