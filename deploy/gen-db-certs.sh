#!/usr/bin/env bash
# สร้างใบรับรอง TLS แบบ self-signed ให้ PostgreSQL บนเครื่องฐานข้อมูล
# ใช้: ./deploy/gen-db-certs.sh 10.0.0.20
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="$ROOT/db/certs"

HOST="${1:-}"
if [[ -z "$HOST" && -f "$ROOT/deploy/deploy.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/deploy/deploy.env"
  HOST="${DB_INTERNAL_IP:-}"
fi

if [[ -z "$HOST" ]]; then
  echo "ใช้: $0 <ip-หรือ-hostname-ของเครื่องฐานข้อมูล>" >&2
  echo "หรือกำหนด DB_INTERNAL_IP ใน deploy/deploy.env" >&2
  exit 1
fi

if [[ -f "$CERT_DIR/server.crt" ]]; then
  echo "มีใบรับรองอยู่แล้วที่ $CERT_DIR/server.crt"
  openssl x509 -in "$CERT_DIR/server.crt" -noout -subject -enddate
  read -r -p "ออกใบใหม่ทับของเดิมหรือไม่? [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "ยกเลิก"; exit 0; }
fi

# ถ้าเป็นตัวเลขล้วนคั่นจุด ให้ใส่เป็น IP ใน SAN ไม่ใช่ DNS
if [[ "$HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  SAN="IP:$HOST"
else
  SAN="DNS:$HOST"
fi

mkdir -p "$CERT_DIR"
openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
  -keyout "$CERT_DIR/server.key" \
  -out    "$CERT_DIR/server.crt" \
  -subj   "/CN=$HOST" \
  -addext "subjectAltName=$SAN" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth" 2>/dev/null

chmod 600 "$CERT_DIR/server.key"
chmod 644 "$CERT_DIR/server.crt"

echo "สร้างใบรับรองสำหรับ $HOST เรียบร้อย ($CERT_DIR)"
openssl x509 -in "$CERT_DIR/server.crt" -noout -subject -enddate
echo
echo "หมายเหตุ: เป็นใบรับรองที่เซ็นเอง ฝั่ง app จึงต้องใช้ DB_SSLMODE=require (เข้ารหัสแต่ไม่ตรวจใบรับรอง)"
echo "ถ้าต้องการ verify-full ให้ใช้ใบรับรองจาก CA ภายในองค์กรแทน"
