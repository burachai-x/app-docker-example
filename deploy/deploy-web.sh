#!/usr/bin/env bash
# ส่งโค้ดขึ้นเครื่อง production ฝั่ง web แล้วสั่ง docker compose up
# ใช้: ./deploy/deploy-web.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[[ -f deploy/deploy.env ]] || { echo "ไม่พบ deploy/deploy.env — คัดลอกจาก deploy/deploy.env.example ก่อน" >&2; exit 1; }
# shellcheck disable=SC1091
source deploy/deploy.env

: "${WEB_SSH:?ต้องกำหนด WEB_SSH ใน deploy/deploy.env}"
REMOTE_DIR="${WEB_REMOTE_DIR:-/opt/app-docker-example}"
COMPOSE="docker compose -f compose.yaml -f compose.prod.web.yaml"

echo "==> เครื่องปลายทาง: $WEB_SSH:$REMOTE_DIR"
ssh "$WEB_SSH" "mkdir -p '$REMOTE_DIR'" || {
  echo "สร้างโฟลเดอร์ไม่ได้ — ให้ผู้ดูแลรัน: sudo mkdir -p $REMOTE_DIR && sudo chown \$USER $REMOTE_DIR" >&2
  exit 1
}

echo "==> คัดลอกไฟล์ (rsync)"
# --exclude .env ทำให้ค่า config บนเครื่อง production ไม่ถูกเขียนทับและไม่ถูกลบโดย --delete
rsync -az --delete \
  --exclude '.git/' \
  --exclude '.env' \
  --exclude 'node_modules/' \
  --exclude 'db/certs/' \
  --exclude 'db/backups/' \
  --exclude 'deploy/deploy.env' \
  app nginx compose.yaml compose.prod.web.yaml Makefile \
  "$WEB_SSH:$REMOTE_DIR/"

echo "==> ตรวจไฟล์ .env บนเครื่องปลายทาง"
if ! ssh "$WEB_SSH" "test -f '$REMOTE_DIR/.env'"; then
  echo "ยังไม่มี .env บนเครื่อง web — กำลังคัดลอกไฟล์ตัวอย่างไปให้"
  scp env/prod.web.env.example "$WEB_SSH:$REMOTE_DIR/.env"
  ssh "$WEB_SSH" "chmod 600 '$REMOTE_DIR/.env'"
  echo
  echo "!! หยุดตรงนี้ก่อน: ไปแก้ค่าใน $REMOTE_DIR/.env (อย่างน้อยคือ DB_HOST และ POSTGRES_PASSWORD)"
  echo "   แล้วสั่ง $0 ซ้ำอีกครั้ง"
  exit 1
fi

echo "==> build + up"
ssh "$WEB_SSH" "cd '$REMOTE_DIR' && $COMPOSE up -d --build --remove-orphans"

echo "==> สถานะ"
ssh "$WEB_SSH" "cd '$REMOTE_DIR' && $COMPOSE ps"

echo "==> ตรวจ health ผ่าน nginx"
# อ่านพอร์ตจาก .env ของเครื่องปลายทาง (ไม่ source เพราะค่าบางตัวอาจมีอักขระที่ shell ตีความ)
REMOTE_HTTP_PORT="$(ssh "$WEB_SSH" "grep -E '^HTTP_PORT=' '$REMOTE_DIR/.env' | tail -1 | cut -d= -f2" | tr -d '\r' || true)"
REMOTE_HTTP_PORT="${REMOTE_HTTP_PORT:-80}"
if ssh "$WEB_SSH" "curl -fsS -m 10 http://127.0.0.1:$REMOTE_HTTP_PORT/readyz"; then
  echo
  echo "deploy สำเร็จ"
else
  echo
  echo "!! /readyz ยังไม่ผ่าน ดู log ด้วย: ssh $WEB_SSH 'cd $REMOTE_DIR && $COMPOSE logs --tail=50 app'" >&2
  exit 1
fi
