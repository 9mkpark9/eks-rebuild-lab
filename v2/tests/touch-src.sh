#!/usr/bin/env bash
# 빌드 측정용: 소스 파일 끝에 주석 한 줄을 덧붙인다 (매번 내용이 달라야 Docker 가 "바뀌었다"고 본다). 덧붙인 줄을 보여 준다.
# 되돌리기: git checkout -- <파일>
#   v2/tests/touch-src.sh msa/auth-service/src/main/java/kr/bodeum/vet/AuthServiceApplication.java
line="    // touch $(date +%s%N)"
echo "$line" >> "$1"
echo "소스 한 줄 덧붙임: $1 ← '$line'"
