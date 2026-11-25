#!/usr/bin/env bash
# 표준 입력을 받아 가릴 값(비밀번호, 12자리 AWS 계정 번호, 공인 IP, PC 이름)을 가려서 내보낸다. 화면 캡처용.
#   kubectl get nodes -o wide | v2/tests/mask.sh
. "$(dirname "${BASH_SOURCE[0]}")/cap.sh"
_cap_mask
