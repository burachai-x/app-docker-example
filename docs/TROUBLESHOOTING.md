# ปัญหาที่เจอบ่อย

## คอนเทนเนอร์ฐานข้อมูลไม่ยอมขึ้น แล้วขึ้นว่า "unused mount/volume"

```
Error: in 18+, these Docker images are configured to store database data in a
       format which is compatible with "pg_ctlcluster" ...
       Counter to that, there appears to be PostgreSQL data in:
         /var/lib/postgresql/data (unused mount/volume)
```

**สาเหตุ** PostgreSQL 18 เปลี่ยนตำแหน่งที่ควร mount volume จาก `/var/lib/postgresql/data`
มาเป็น `/var/lib/postgresql` (image จะสร้างโฟลเดอร์ย่อยตามเวอร์ชันให้เอง เพื่อให้ `pg_upgrade` ทำงานได้)

**แก้** ใช้ `- pgdata:/var/lib/postgresql` แบบที่ `compose.dev.yaml` ทำไว้
ถ้าเพิ่งเจอตอนอัปเกรดจาก 17 ขึ้น 18 ห้ามลบ volume ทิ้ง ให้ทำ `pg_dump` จาก image เก่าก่อน แล้ว restore เข้า image ใหม่

---

## app สตาร์ตไม่ขึ้นเพราะต่อฐานข้อมูลไม่ได้ ทั้งที่ `docker compose ps` บอกว่า db healthy

**สาเหตุที่พบบ่อยที่สุด** `pg_isready` ที่ไม่ใส่ `-h` จะเช็คผ่าน unix socket ในคอนเทนเนอร์
ซึ่งพร้อมก่อนที่ PostgreSQL จะเปิดรับ TCP — healthcheck เลยเขียว ทั้งที่ยังต่อผ่านเครือข่ายไม่ได้

**แก้** ใส่ `-h 127.0.0.1` เสมอ:

```yaml
test: ["CMD-SHELL", "pg_isready -h 127.0.0.1 -U appuser -d appdb"]
```

---

## nginx ดับทันทีที่สตาร์ต: `host not found in upstream "app"`

**สาเหตุ** ถ้าเขียน `proxy_pass http://app:3000;` ตรง ๆ nginx จะ resolve ชื่อนี้ **ตอนอ่าน config**
ถ้าคอนเทนเนอร์ `app` ยังไม่ขึ้น nginx จะถือว่า config ผิดแล้วดับไปเลย

**แก้** (ทำไว้แล้วในไฟล์ conf ของโปรเจกต์นี้) ให้ resolve ตอนมี request จริง โดยใช้ DNS ของ Docker:

```nginx
resolver 127.0.0.11 valid=10s ipv6=off;
set $upstream_app app:3000;
proxy_pass http://$upstream_app$request_uri;
```

ผลคือ nginx ขึ้นได้เสมอ ถ้า app ยังไม่พร้อมจะตอบ 502 ชั่วคราวแล้วหายเองเมื่อ app ขึ้น

---

## แก้ไฟล์ใน `db/init/` แล้วไม่มีอะไรเปลี่ยน

ไฟล์ใน `/docker-entrypoint-initdb.d` รัน **ครั้งเดียวตอน data directory ยังว่าง** เท่านั้น
ฐานข้อมูลที่มีข้อมูลแล้วจะข้ามไปทั้งหมด

- บนเครื่องเดฟ: `make reset` (ข้อมูลหาย) หรือสั่ง SQL เองผ่าน `make psql`
- การเปลี่ยน schema ที่ถูกวิธี: เขียนไฟล์ใหม่ใน `app/migrations/`

---

## `docker compose up` บน production ฟ้องว่า `DB_HOST` ไม่ถูกกำหนด

```
error while interpolating services.app.environment.DB_HOST:
required variable DB_HOST is missing a value: ต้องกำหนด DB_HOST = IP ภายในของเครื่องฐานข้อมูล
```

นี่คือพฤติกรรมที่ตั้งใจให้เป็น — ตัวแปรของ production เขียนเป็น `${VAR:?ข้อความ}` เพื่อให้ **ล้มตั้งแต่ยังไม่สตาร์ต**
แทนที่จะขึ้นไปครึ่ง ๆ กลาง ๆ แล้วค่อยพังตอนมีผู้ใช้

**แก้** ตรวจว่ามีไฟล์ `.env` อยู่ในโฟลเดอร์เดียวกับไฟล์ compose และสั่ง `docker compose` จากโฟลเดอร์นั้น
(compose อ่าน `.env` จาก working directory ไม่ใช่จากที่อยู่ของไฟล์ compose)

---

## app ต่อฐานข้อมูลไม่ได้: `no pg_hba.conf entry ... no encryption`

ฝั่งฐานข้อมูลบังคับ TLS แต่ฝั่ง app ต่อแบบไม่เข้ารหัส

**แก้** ตั้ง `DB_SSLMODE=require` ใน `.env` ของเครื่อง web (ค่า default ของ `compose.prod.web.yaml` เป็น `require` อยู่แล้ว
อาการนี้มักเกิดตอนมีใครไปตั้งทับเป็น `disable` เพื่อลองแก้ปัญหา)

---

## คอนเทนเนอร์ฐานข้อมูลบน production ไม่ยอมขึ้น: `ไม่พบ /certs/server.key`

ยังไม่ได้ออกใบรับรอง TLS

```bash
./deploy/gen-db-certs.sh <IP ของเครื่องฐานข้อมูล>
make deploy-db
```

---

## ต่อฐานข้อมูลจากเครื่อง web ไม่ได้ ทั้งที่คอนเทนเนอร์ db ขึ้นปกติ

ไล่ทีละชั้น:

```bash
# 1) พอร์ตเปิดอยู่บน IP ที่คิดไว้จริงไหม (บนเครื่อง db)
ss -ltnp | grep 5432
# ต้องเห็น 10.0.0.20:5432 ไม่ใช่ 127.0.0.1:5432

# 2) จากเครื่อง web ถึงกันไหม
nc -vz 10.0.0.20 5432

# 3) ไฟร์วอลล์
sudo ufw status | grep 5432

# 4) pg_hba อนุญาต IP นี้ไหม (บนเครื่อง db)
docker compose -f compose.prod.db.yaml exec db cat /etc/postgresql/pg_hba.conf
```

ถ้าข้อ 1 เห็นเป็น `127.0.0.1:5432` แปลว่า `DB_BIND_ADDRESS` ใน `.env` ผิด

---

## ดิสก์เต็มเพราะ log

log ของ docker (driver `json-file`) จะโตไปเรื่อย ๆ ถ้าไม่จำกัด ไฟล์ compose ของ production ตั้ง `max-size`/`max-file` ไว้แล้ว

**อย่าใช้ `logrotate` กับไฟล์ log ของ docker** — `copytruncate` จะทำให้ `docker logs` ค้างและ log หาย
ถ้าต้องเปลี่ยนค่า ให้แก้ที่ `logging.options` แล้ว **recreate คอนเทนเนอร์** (ค่านี้มีผลตอนสร้างคอนเทนเนอร์เท่านั้น)

```bash
docker compose -f compose.yaml -f compose.prod.web.yaml up -d --force-recreate
```

---

## พอร์ตชนกับโปรเจกต์อื่นบนเครื่องเดฟ

```
Error starting userland proxy: listen tcp4 0.0.0.0:8080: bind: address already in use
```

```bash
cp env/dev.env.example .env
$EDITOR .env        # เปลี่ยน WEB_PORT / APP_PORT / DB_PORT_HOST
make up
```

---

## แก้โค้ดแล้วไม่รีโหลด

1. ดูว่าแก้ไฟล์ใน `app/src/` จริงไหม (โฟลเดอร์อื่นไม่ได้ถูก mount)
2. ดู log ว่ามีบรรทัด `Restarting 'src/server.js'` ไหม
3. ถ้าแก้ `package.json` หรือ `Dockerfile` ต้อง `make up` เพื่อ build ใหม่
4. ถ้าใช้ตัวแก้ไขที่เขียนไฟล์แบบ atomic (สร้างไฟล์ใหม่แล้วเปลี่ยนชื่อทับ) บางครั้ง watcher จับไม่ได้ ให้ `make up` แทน
