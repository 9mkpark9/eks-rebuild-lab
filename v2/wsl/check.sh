#!/usr/bin/env bash
# ①② 를 WSL 2 Ubuntu 에서 하기 전에, 무엇이 설치돼 있는지 본다.
#   wsl -d Ubuntu -- bash /mnt/c/.../v2/wsl/check.sh
echo "OS:      $(. /etc/os-release; echo "$PRETTY_NAME")  (커널 $(uname -r))"
echo "사용자:  $(whoami)"
echo "systemd: $(ps -p 1 -o comm=)"
for c in java javac node npm docker git curl unzip; do
    p=$(command -v "$c" 2>/dev/null)
    printf '%-7s %s\n' "$c:" "${p:-없음}"
done
command -v java > /dev/null && java -version 2>&1 | head -1
command -v node > /dev/null && node --version
if command -v docker > /dev/null; then
    docker version --format 'docker: 클라이언트 {{.Client.Version}} / 서버 {{.Server.Version}} ({{.Server.Os}})' 2>&1 | head -2
    docker info --format '컨텍스트 OS: {{.OperatingSystem}}, 이름: {{.Name}}' 2>&1 | head -1
    systemctl is-active docker 2>/dev/null | sed 's/^/docker 서비스: /'
    readlink -f "$(command -v docker)"
fi
free -h | sed -n 1,2p
nproc | sed 's/^/CPU: /'
