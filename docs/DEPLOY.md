# ขั้นตอน deploy ขึ้น production (เครื่อง web + เครื่องฐานข้อมูล)

เอกสารนี้ไล่ตั้งแต่เครื่องเปล่าจนระบบเปิดให้บริการได้ ทำตามลำดับ **เครื่องฐานข้อมูลก่อน** เสมอ
เพราะเครื่อง web จะรัน migration ตอนสตาร์ต ถ้าฐานข้อมูลยังไม่พร้อม app จะสตาร์ตไม่ผ่าน

สมมติฐานที่ใช้ตลอดเอกสาร:

| | IP วงภายใน | หน้าที่ |
|---|---|---|
| เครื่อง web | `10.0.0.10` | nginx + app รับทราฟฟิกจากภายนอก |
| เครื่อง db | `10.0.0.20` | PostgreSQL + งานสำรองข้อมูล |

---

## 0. เตรียมทั้งสองเครื่อง (ทำครั้งเดียว)

บนทั้งสองเครื่อง:

```bash
# ติดตั้ง Docker Engine + compose plugin
curl -fsSL https://get.docker.com | sudo sh

# ให้ user ที่ใช้ deploy สั่ง docker ได้โดยไม่ต้อง sudo
sudo usermod -aG docker $USER
newgrp docker

# สร้างโฟลเดอร์ปลายทาง
sudo mkdir -p /opt/app-docker-example        # เครื่อง web
sudo mkdir -p /opt/app-docker-example-db     # เครื่อง db
sudo chown $USER /opt/app-docker-example*
```

บนเครื่องที่ใช้สั่ง deploy (เครื่องเดฟ) ต้อง `ssh` เข้าทั้งสองเครื่องได้ด้วยคีย์ ไม่ใช่รหัสผ่าน:

```bash
ssh-copy-id deploy@10.0.0.10
ssh-copy-id deploy@10.0.0.20
```

แล้วตั้งค่าปลายทาง:

```bash
cp deploy/deploy.env.example deploy/deploy.env
$EDITOR deploy/deploy.env       # ใส่ WEB_SSH, DB_SSH, DB_INTERNAL_IP
```

---

## 1. ไฟร์วอลล์ — ทำก่อนเปิดฐานข้อมูล

ฐานข้อมูลต้องรับการต่อจากเครื่อง web **เครื่องเดียวเท่านั้น**

```bash
# บนเครื่อง db
sudo ufw allow from 10.0.0.10 to any port 5432 proto tcp
sudo ufw enable
```

> **ระวังเมื่อเครื่องนั้นมี Docker:** กฎของ `ufw`/`iptables` ปกติจะถูก Docker ข้ามไป เพราะ Docker แทรกกฎของตัวเองไว้ก่อน
> ถ้าต้องการกรองทราฟฟิกที่วิ่งเข้าคอนเทนเนอร์จริง ๆ ต้องเขียนกฎในเชน `DOCKER-USER` และต้องใช้ `--ctorigdstport` ไม่ใช่ `--dport`
> เพราะตอนแพ็กเก็ตมาถึงเชนนี้ปลายทางถูก DNAT ไปเป็น IP ภายในของคอนเทนเนอร์แล้ว
>
> ```bash
> sudo iptables -I DOCKER-USER -p tcp -m conntrack --ctorigdstport 5432 \
>      ! -s 10.0.0.10 -j DROP
> ```
>
> ทางที่ปลอดภัยกว่าและง่ายกว่าคือ **ผูกพอร์ตกับ IP วงภายในตั้งแต่แรก** ซึ่ง `compose.prod.db.yaml` ทำไว้ให้แล้วผ่าน `DB_BIND_ADDRESS`

---

## 2. เครื่องฐานข้อมูล

### 2.1 ออกใบรับรอง TLS

การต่อฐานข้อมูลข้ามเครื่องต้องเข้ารหัส ไม่งั้นรหัสผ่านและข้อมูลวิ่งเปลือยอยู่ในวง LAN

```bash
# สั่งจากเครื่องเดฟ (ใส่ IP ของเครื่องฐานข้อมูล)
./deploy/gen-db-certs.sh 10.0.0.20
```

ได้ไฟล์ `db/certs/server.crt` และ `server.key` ซึ่ง **ไม่ถูก commit ขึ้น git** และสคริปต์ deploy จะคัดลอกขึ้นเครื่องปลายทางให้เอง

### 2.2 deploy

```bash
make deploy-db
```

ครั้งแรกสคริปต์จะคัดลอก `.env` ตัวอย่างไปวางแล้วหยุด ให้เข้าไปแก้ค่า:

```bash
ssh deploy@10.0.0.20
$EDITOR /opt/app-docker-example-db/.env
```

ค่าที่ต้องแก้อย่างน้อย:

```ini
DB_BIND_ADDRESS=10.0.0.20     # IP วงภายในของเครื่องนี้ ห้ามเป็น 0.0.0.0
POSTGRES_PASSWORD=<รหัสผ่านจริง ไม่มีช่องว่าง>
PG_SHARED_BUFFERS=2GB         # ประมาณ 25% ของ RAM
```

แล้วสั่ง `make deploy-db` ซ้ำอีกครั้ง

### 2.3 ตรวจว่าขึ้นจริง

```bash
ssh deploy@10.0.0.20 'cd /opt/app-docker-example-db && docker compose -f compose.prod.db.yaml ps'
```

ต้องเห็น `db` เป็น `Up (healthy)` และ `backup` เป็น `Up`

ทดสอบว่ากติกา TLS มีผลจริง (รันจากเครื่อง web):

```bash
# แบบไม่เข้ารหัส -> ต้องถูกปฏิเสธ
docker run --rm -e PGPASSWORD=<รหัสผ่าน> postgres:18-alpine \
  psql "host=10.0.0.20 user=appuser dbname=appdb sslmode=disable" -c "select 1"
# คาดหวัง: pg_hba.conf rejects connection ... no encryption

# แบบเข้ารหัส -> ต้องผ่าน
docker run --rm -e PGPASSWORD=<รหัสผ่าน> postgres:18-alpine \
  psql "host=10.0.0.20 user=appuser dbname=appdb sslmode=require" -c "select version()"
```

### 2.4 จำกัดสิทธิ์ให้แคบลง (แนะนำ)

`db/conf/pg_hba.conf` ที่ให้มาเปิดกว้างไว้ที่ `0.0.0.0/0` เพื่อให้ทดลองได้ง่าย เมื่อรู้ IP จริงแล้วให้แก้เป็น

```
hostssl  all  all  10.0.0.10/32  scram-sha-256
```

แล้ว `make deploy-db` ใหม่ (ไม่ต้องลบข้อมูล แค่คอนเทนเนอร์สตาร์ตใหม่)

---

## 3. เครื่อง web

```bash
make deploy-web
```

ครั้งแรกจะหยุดให้ไปแก้ `.env` เช่นกัน:

```bash
ssh deploy@10.0.0.10
$EDITOR /opt/app-docker-example/.env
```

```ini
HTTP_PORT=80
DB_HOST=10.0.0.20                # IP ของเครื่องฐานข้อมูล
POSTGRES_PASSWORD=<ให้ตรงกับเครื่อง db>
DB_SSLMODE=require
```

แล้วสั่ง `make deploy-web` ซ้ำ สคริปต์จะจบด้วยการเรียก `/readyz` ให้เอง — ถ้าขึ้น `"status":"ready"` แปลว่า nginx, app และฐานข้อมูลข้ามเครื่องต่อกันครบแล้ว

ตรวจซ้ำจากเครื่องตัวเองได้ด้วย:

```bash
./deploy/smoke-test.sh http://<โดเมนหรือ IP สาธารณะ>
```

---

## 4. เปิด HTTPS

1. ชี้โดเมนมาที่ IP สาธารณะของเครื่อง web
2. ออกใบรับรองบนเครื่อง web:

   ```bash
   sudo certbot certonly --standalone -d example.com
   ```

3. แก้ `compose.prod.web.yaml` ส่วน `nginx` ให้เปิดพอร์ต 443 และ mount ใบรับรอง:

   ```yaml
   ports:
     - "80:80"
     - "443:443"
   volumes:
     - ./nginx/conf.d/prod-tls.conf.example:/etc/nginx/conf.d/default.conf:ro
     - /etc/letsencrypt:/etc/letsencrypt:ro
   ```

4. แก้ `server_name` ในไฟล์ conf ให้เป็นโดเมนจริง แล้ว `make deploy-web`

---

## 5. งานประจำหลัง deploy

### ดู log

```bash
ssh deploy@10.0.0.10 'cd /opt/app-docker-example && docker compose -f compose.yaml -f compose.prod.web.yaml logs -f --tail=100 app'
```

### กู้คืนข้อมูลจากไฟล์สำรอง

ไฟล์ dump อยู่ที่ `/opt/app-docker-example-db/db/backups/` บนเครื่องฐานข้อมูล

```bash
ssh deploy@10.0.0.20
cd /opt/app-docker-example-db
ls -lh db/backups/

# กู้ทับฐานเดิม (ระวัง: ข้อมูลปัจจุบันจะถูกแทนที่)
docker compose -f compose.prod.db.yaml exec -T db \
  pg_restore -U appuser -d appdb --clean --if-exists < db/backups/appdb-20260101-030000.dump
```

> ไฟล์ dump อยู่บนเครื่องเดียวกับฐานข้อมูล ถ้าดิสก์เครื่องนั้นเสียก็หายไปพร้อมกัน
> ควรตั้งงานคัดลอกออกไปเก็บนอกเครื่อง เช่น `rsync` ขึ้น NAS หรือ object storage

### อัปเดตเวอร์ชันแอป

```bash
git pull
make deploy-web        # build image ใหม่บนเครื่อง web แล้วสลับคอนเทนเนอร์ให้เอง
```

migration ใหม่จะถูกรันอัตโนมัติตอน app สตาร์ต (ใช้ advisory lock กันการรันซ้อนกัน)

### ถอยกลับเวอร์ชันก่อนหน้า

```bash
git checkout <commit-ก่อนหน้า>
make deploy-web
```

ถ้า migration รอบนั้นแก้โครงสร้างตารางไปแล้ว การถอยโค้ดอย่างเดียวอาจไม่พอ —
เขียน migration ตัวใหม่ที่ย้อนสิ่งที่ทำไว้ จะปลอดภัยกว่าการกู้ทั้งฐานจากไฟล์สำรอง
