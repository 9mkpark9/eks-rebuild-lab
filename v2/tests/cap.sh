#!/usr/bin/env bash
# 캡처용 기록: 명령을 실행하고, 명령과 출력을 그대로 텍스트로 남긴다. 그림은 v2/tests/render.mjs 가 만든다.
# WSL 2 Ubuntu 와 Windows(Git Bash) 어디서든 쓴다. 출력은 화면에도 그대로 나온다.
#
#   . v2/tests/cap.sh                                   (함수를 불러온다)
#   cap <파일 이름> "<제목>" <명령...>                     명령 하나를 기록 (종료 코드를 그대로 돌려준다)
#   cap_note <파일 이름> "<제목>" "<설명 줄>" < 텍스트     이미 있는 출력(예: 지난 실행 기록)을 기록
#
# 남기기 전에 가리는 것: v2/_run/secrets.env 의 비밀번호, 12자리 AWS 계정 번호, 공인 IP, 이 PC 의 사용자·호스트 이름,
# RDS 주소의 고유 부분. 가린 결과만 파일에 남는다.
_CAP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CAP_DIR="${CAP_DIR:-$_CAP_ROOT/v2/_run/capture}"
mkdir -p "$CAP_DIR"
CAP_ENV="${CAP_ENV:-$( [ -n "${WSL_DISTRO_NAME:-}" ] && echo "WSL 2 $(. /etc/os-release; echo "$PRETTY_NAME")" || echo "Windows 11 · Git Bash")}"

_cap_mask() {
    local sed_args=() v
    if [ -f "$_CAP_ROOT/v2/_run/secrets.env" ]; then
        while IFS='=' read -r _ v; do [ -n "$v" ] && sed_args+=(-e "s#${v}#********#g"); done < "$_CAP_ROOT/v2/_run/secrets.env"
    fi
    sed "${sed_args[@]}" \
        -e 's/[0-9]\{12\}\.dkr/************.dkr/g' -e 's/::[0-9]\{12\}:/::************:/g' -e 's/\b[0-9]\{12\}\b/************/g' \
        -e 's/vet2-db\.[a-z0-9]\{12\}\./vet2-db.<id>./g' \
        -e 's/junseo-desktop/my-pc/g' -e 's#/home/junseo#/home/me#g' -e 's#C:\\Users\\junseo#C:\\Users\\me#g' -e 's#/c/Users/junseo#/c/Users/me#g' -e 's#C:/Users/junseo#C:/Users/me#g' -e 's/\bjunseo\b/me/g' \
        -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' |
    # 공인 IPv4 만 가린다. 사설(10/8, 172.16/12, 192.168/16), 127/8, 0.0.0.0, 점이 더 붙은 버전 번호(21.0.13.0.3)는 그대로 둔다
    perl -pe 's/(?<![\d.])(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?![\d.])/ ($1==10||$1==127||$1==0||($1==172&&$2>=16&&$2<=31)||($1==192&&$2==168)||$1>255||$2>255||$3>255||$4>255) ? "$1.$2.$3.$4" : "<IP>" /ge'
}
cap() {
    local name="$1" title="$2"; shift 2
    local out="$CAP_DIR/$name.txt" raw rc
    raw="$(mktemp)"
    { echo "#title: $title"; echo "#env: $CAP_ENV · $(date '+%Y-%m-%d %H:%M')"; echo "\$ $*"; } > "$raw.head"
    "$@" > "$raw" 2>&1; rc=$?
    cat "$raw"
    { cat "$raw.head"; cat "$raw"; [ $rc -ne 0 ] && echo "#exit: $rc"; } | _cap_mask > "$out"
    rm -f "$raw" "$raw.head"
    return $rc
}

cap_note() {
    local name="$1" title="$2" note="$3"
    { echo "#title: $title"; echo "#env: $note"; cat; } | _cap_mask > "$CAP_DIR/$name.txt"
}
