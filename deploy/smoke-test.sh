#!/usr/bin/env bash
# ทดสอบว่า nginx -> app -> postgres ต่อกันครบวงจรจริง
# ใช้: ./deploy/smoke-test.sh http://localhost:8080
set -euo pipefail

BASE="${1:-http://localhost:8080}"
fail=0

check() {
  local name="$1" cmd="$2"
  # ไม่ใช้ printf %-Ns จัดคอลัมน์ เพราะมันนับไบต์ ทำให้ข้อความไทยเยื้องไม่ตรง
  if out="$(eval "$cmd" 2>&1)"; then
    echo "  [ผ่าน]    $name"
  else
    echo "  [ไม่ผ่าน] $name"
    echo "            -> $out"
    fail=1
  fi
}

echo "ทดสอบที่ $BASE"

check "หน้าเว็บ static จาก nginx" \
  "curl -fsS -m 10 '$BASE/' | grep -q app-docker-example"

check "app ยังมีชีวิต (/healthz)" \
  "curl -fsS -m 10 '$BASE/healthz' | grep -q '\"status\":\"ok\"'"

check "app ต่อฐานข้อมูลได้ (/readyz)" \
  "curl -fsS -m 10 '$BASE/readyz' | grep -q '\"status\":\"ready\"'"

msg="smoke-test $(date +%Y%m%d-%H%M%S)"
check "เขียนข้อมูลลงฐานข้อมูล (POST)" \
  "curl -fsS -m 10 -X POST '$BASE/api/messages' -H 'content-type: application/json' -d '{\"body\":\"$msg\"}' | grep -q '\"id\"'"

check "อ่านข้อมูลที่เพิ่งเขียนกลับมา (GET)" \
  "curl -fsS -m 10 '$BASE/api/messages' | grep -q '$msg'"

check "ข้อมูลไม่ครบต้องถูกปฏิเสธ (400)" \
  "test \"\$(curl -s -o /dev/null -w '%{http_code}' -m 10 -X POST '$BASE/api/messages' -H 'content-type: application/json' -d '{}')\" = 400"

echo
if [[ $fail -eq 0 ]]; then
  echo "ทุกข้อผ่าน"
else
  echo "มีข้อที่ไม่ผ่าน — ดู log ด้วย: docker compose -f compose.yaml -f compose.dev.yaml logs --tail=50" >&2
  exit 1
fi
