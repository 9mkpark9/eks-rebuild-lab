#!/usr/bin/env bash
# 시연에서 만든 예약(owner001, 콩이, 지정한 날짜)을 취소한다
set -u
A1=$(grep -o "A1=[^ ]*" "$(dirname "$0")/../../_run/alb.env" | cut -d= -f2); B="http://$A1"; D="$1"
J=$(mktemp); curl -s -o /dev/null -c "$J" -H 'Content-Type: application/json' -d '{"loginId":"owner001","password":"test-only"}' "$B/api/auth/login"
curl -s -b "$J" "$B/api/reservations/me" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);const a=Array.isArray(j)?j:(j.items||j.content||[]);
for(const r of a){ if(r.petName==="콩이" && String(r.visitDate||r.startAt).startsWith(process.argv[1]) && r.status!=="CANCELLED") console.log(r.reservationId)}})' "$D" | while read id; do
  echo "취소: $id $(curl -s -o /dev/null -w %{http_code} -b "$J" -X DELETE "$B/api/reservations/$id")"; done
rm -f "$J"
