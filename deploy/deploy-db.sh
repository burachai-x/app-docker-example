#!/usr/bin/env bash
# ส่ง config ขึ้นเครื่อง production ฝั่งฐานข้อมูล แล้วสั่ง docker compose up
# ใช้: ./deploy/deploy-db.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[[ -f deploy/deploy.env ]] || { echo "ไม่พบ deploy/deploy.env — คัดลอกจาก deploy/deploy.env.example ก่อน" >&2; exit 1; }
# shellcheck disable=SC1091
source deploy/deploy.env

: "${DB_SSH:?ต้องกำหนด DB_SSH ใน deploy/deploy.env}"
REMOTE_DIR="${DB_REMOTE_DIR:-/opt/app-docker-example-db}"
COMPOSE="docker compose -f compose.prod.db.yaml"

# ใบรับรองต้องมีก่อน ไม่งั้นคอนเทนเนอร์จะไม่ยอมสตาร์ต
if [[ ! -f db/certs/server.key ]]; then
  echo "==> ยังไม่มีใบรับรอง TLS กำลังสร้างให้"
  ./deploy/gen-db-certs.sh "${DB_INTERNAL_IP:-}"
fi

echo "==> เครื่องปลายทาง: $DB_SSH:$REMOTE_DIR"
ssh "$DB_SSH" "mkdir -p '$REMOTE_DIR/db/backups' '$REMOTE_DIR/db/certs'" || {
  echo "สร้างโฟลเดอร์ไม่ได้ — ให้ผู้ดูแลรัน: sudo mkdir -p $REMOTE_DIR && sudo chown \$USER $REMOTE_DIR" >&2
  exit 1
}

echo "==> คัดลอก config"
rsync -az --delete \
  --exclude '.env' \
  --exclude 'db/backups/' \
  --exclude 'db/certs/' \
  db compose.prod.db.yaml \
  "$DB_SSH:$REMOTE_DIR/"

echo "==> คัดลอกใบรับรอง (ไม่ผ่าน git)"
rsync -az db/certs/server.crt db/certs/server.key "$DB_SSH:$REMOTE_DIR/db/certs/"

echo "==> ตรวจไฟล์ .env บนเครื่องปลายทาง"
if ! ssh "$DB_SSH" "test -f '$REMOTE_DIR/.env'"; then
  echo "ยังไม่มี .env บนเครื่องฐานข้อมูล — กำลังคัดลอกไฟล์ตัวอย่างไปให้"
  scp env/prod.db.env.example "$DB_SSH:$REMOTE_DIR/.env"
  ssh "$DB_SSH" "chmod 600 '$REMOTE_DIR/.env'"
  echo
  echo "!! หยุดตรงนี้ก่อน: ไปแก้ค่าใน $REMOTE_DIR/.env (อย่างน้อยคือ DB_BIND_ADDRESS และ POSTGRES_PASSWORD)"
  echo "   แล้วสั่ง $0 ซ้ำอีกครั้ง"
  exit 1
fi

echo "==> up"
ssh "$DB_SSH" "cd '$REMOTE_DIR' && $COMPOSE up -d --remove-orphans"

echo "==> สถานะ"
ssh "$DB_SSH" "cd '$REMOTE_DIR' && $COMPOSE ps"

echo
echo "เสร็จแล้ว อย่าลืมเปิดไฟร์วอลล์ให้เฉพาะเครื่อง web ต่อพอร์ต 5432 ได้ เช่น"
echo "  ssh $DB_SSH 'sudo ufw allow from <IP-เครื่อง-web> to any port 5432 proto tcp'"
