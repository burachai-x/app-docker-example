# app-docker-example

ตัวอย่างโครงสร้างโปรเจกต์ **nginx + Node.js (Express) + PostgreSQL** ด้วย Docker Compose
ที่ออกแบบมาให้ตอบโจทย์เดียวกันทั้งสองแบบ:

- **เครื่องเดฟ** — สั่งคำสั่งเดียว ได้ครบทั้งสามตัวในเครื่องตัวเอง
- **production** — เครื่อง web (nginx + app) กับเครื่องฐานข้อมูล (PostgreSQL) แยกคนละเครื่อง

โค้ดแอปเป็นชุดเดียวกันทั้งหมด ไม่มี `if (production)` ซ่อนอยู่ที่ไหน — สิ่งที่ต่างกันมีแค่ **ไฟล์ compose ที่ซ้อนทับ** กับ **ค่าใน `.env`** เท่านั้น

---

## เริ่มใช้งานบนเครื่องเดฟ

```bash
git clone https://github.com/burachai-x/app-docker-example.git
cd app-docker-example
make dev            # เท่ากับ docker compose -f compose.yaml -f compose.dev.yaml up --build
```

เปิด <http://localhost:8080> จะเห็นหน้าเว็บที่บันทึกข้อความลง PostgreSQL ได้

ไม่ต้องสร้างไฟล์ `.env` ไม่ต้องติดตั้ง Node หรือ PostgreSQL ในเครื่อง — ค่า default อยู่ใน `compose.dev.yaml` ครบแล้ว

> **พอร์ตชนกับโปรเจกต์อื่น?** `cp env/dev.env.example .env` แล้วแก้ `WEB_PORT`, `APP_PORT`, `DB_PORT_HOST`

ตรวจว่าทุกชิ้นต่อกันติดจริง:

```bash
make smoke
```

---

## ภาพรวมสถาปัตยกรรม

### เครื่องเดฟ — ทุกอย่างอยู่ใน network เดียว

```
        เครื่องเดฟของคุณ
┌──────────────────────────────────────────────┐
│  :8080                                       │
│    │                                         │
│    ▼                                         │
│  ┌────────┐   app:3000   ┌─────┐   db:5432   │
│  │ nginx  │─────────────▶│ app │────────────▶│──┐
│  └────────┘              └─────┘             │  │
│    static                Express             │  ▼
│                                        ┌──────────┐
│                                        │ postgres │
│                                        └──────────┘
│  ต่อกันด้วย "ชื่อ service" ผ่าน network ของ compose │
└──────────────────────────────────────────────┘
```

### production — แยกสองเครื่อง

```
   อินเทอร์เน็ต
        │ :80 / :443
        ▼
┌─────────────────────────┐          วงภายใน           ┌──────────────────────────┐
│   เครื่อง WEB            │      TLS + scram-sha-256   │   เครื่อง DATABASE        │
│                         │   :5432                    │                          │
│  ┌────────┐   ┌─────┐   │═══════════════════════════▶│  ┌──────────┐ ┌────────┐ │
│  │ nginx  │──▶│ app │───┼──                          │  │ postgres │ │ backup │ │
│  └────────┘   └─────┘   │                            │  └──────────┘ └────────┘ │
│                         │                            │     ผูกกับ IP วงภายใน     │
│  compose.yaml +         │                            │   compose.prod.db.yaml   │
│  compose.prod.web.yaml  │                            │                          │
└─────────────────────────┘                            └──────────────────────────┘
```

สิ่งที่เปลี่ยนไปจากเครื่องเดฟมีแค่ **`DB_HOST`** — จาก `db` (ชื่อ service) กลายเป็น IP วงภายในของเครื่องฐานข้อมูล

---

## โครงสร้างโฟลเดอร์

```
app-docker-example/
├── compose.yaml              # ฐาน: สิ่งที่เหมือนกันทุกที่ (app + nginx)
├── compose.dev.yaml          # ซ้อนทับสำหรับเครื่องเดฟ (+ postgres, + hot reload, + พอร์ตเปิด)
├── compose.prod.web.yaml     # ซ้อนทับสำหรับเครื่อง web production
├── compose.prod.db.yaml      # ใช้เดี่ยว ๆ บนเครื่องฐานข้อมูล (ไม่ใช้ไฟล์ฐาน)
├── Makefile                  # ทางลัดคำสั่ง พิมพ์ `make` เพื่อดูทั้งหมด
│
├── app/                      # โค้ดแอป — ไม่รู้จักคำว่า dev/prod รู้จักแต่ env
│   ├── Dockerfile            #   multi-stage: target dev และ target prod
│   ├── package.json
│   ├── src/
│   │   ├── config.js         #   รวมการอ่าน env ไว้ที่เดียว
│   │   ├── db.js             #   connection pool + การตั้งค่า TLS
│   │   ├── migrate.js        #   migration runner (มี advisory lock)
│   │   └── server.js         #   route ทั้งหมด + graceful shutdown
│   ├── migrations/           #   *.sql เรียงตามชื่อ — วิธีเปลี่ยน schema ที่ถูกต้อง
│   └── public/               #   ไฟล์ static ที่ nginx เสิร์ฟเอง
│
├── nginx/conf.d/
│   ├── dev.conf              # ไม่ cache, timeout ยาว (เผื่อ debugger)
│   ├── prod.conf             # gzip, cache, security header, /nginx-health
│   └── prod-tls.conf.example # ตัวอย่างเปิด HTTPS ด้วย certbot
│
├── db/
│   ├── init/                 # SQL ที่รันครั้งเดียวตอนสร้างฐานใหม่
│   ├── conf/pg_hba.conf      # บังคับให้ต่อจากเครื่องอื่นต้องผ่าน TLS
│   ├── certs/                # ใบรับรอง TLS (ไม่ขึ้น git)
│   └── backups/              # ไฟล์ dump (ไม่ขึ้น git)
│
├── deploy/
│   ├── deploy-db.sh          # rsync + docker compose up ที่เครื่องฐานข้อมูล
│   ├── deploy-web.sh         # rsync + docker compose up ที่เครื่อง web
│   ├── gen-db-certs.sh       # ออกใบรับรอง self-signed ให้ PostgreSQL
│   ├── smoke-test.sh         # ยิงทดสอบทั้งวงจร ใช้ได้ทั้ง dev และ prod
│   └── deploy.env.example    # ที่อยู่ SSH ของเครื่องปลายทาง
│
├── env/                      # ไฟล์ตัวอย่างของ .env แต่ละสภาพแวดล้อม
│   ├── dev.env.example
│   ├── prod.web.env.example
│   └── prod.db.env.example
│
└── docs/
    ├── DEPLOY.md             # ขั้นตอน deploy ขึ้นสองเครื่อง ละเอียดทีละขั้น
    ├── DEVELOPMENT.md        # งานประจำวันของเดฟ (เพิ่ม lib, เขียน migration, debug)
    └── TROUBLESHOOTING.md    # อาการที่เจอบ่อยและวิธีแก้
```

### กฎการจัดโฟลเดอร์ที่ใช้ที่นี่

1. **แยกตาม "ชิ้นส่วนของระบบ" ไม่ใช่แยกตาม environment** — มี `app/`, `nginx/`, `db/` ชุดเดียว ไม่มี `dev/` กับ `prod/` ที่ต้องคอยไล่ก๊อปไฟล์ให้ตรงกัน
2. **ความต่างของแต่ละ environment อยู่ในไฟล์ compose เท่านั้น** — อยากรู้ว่า prod ต่างจาก dev ตรงไหน เปิดไฟล์เดียวก็เห็นครบ
3. **ความลับอยู่ใน `.env` ที่ไม่ขึ้น git เสมอ** — ใน repo มีแต่ `env/*.env.example`

---

## ไฟล์ compose ใช้ตอนไหน

| สถานการณ์ | คำสั่ง | ได้อะไร |
|---|---|---|
| เครื่องเดฟ | `docker compose -f compose.yaml -f compose.dev.yaml up` | nginx + app + postgres |
| เครื่อง web (prod) | `docker compose -f compose.yaml -f compose.prod.web.yaml up -d` | nginx + app |
| เครื่อง db (prod) | `docker compose -f compose.prod.db.yaml up -d` | postgres + backup |

หลักการซ้อนไฟล์: compose อ่าน `-f` **เรียงจากซ้ายไปขวา** ค่าที่ซ้ำกันไฟล์หลังชนะ ส่วน `volumes` กับ `ports` จะถูกนำมารวมกัน
เช่น `app` ใน `compose.yaml` ใช้ `target: prod` แต่ `compose.dev.yaml` เขียนทับเป็น `target: dev`

> เครื่องฐานข้อมูลไม่ใช้ `compose.yaml` เลย เพราะไม่มี nginx หรือ app อยู่บนเครื่องนั้น

---

## คำสั่งที่ใช้บ่อย

```bash
make            # ดูคำสั่งทั้งหมด
make dev        # สตาร์ตเครื่องเดฟ (ค้าง log ไว้ดู)
make up         # สตาร์ตแบบเบื้องหลัง
make logs       # ดู log ต่อเนื่อง
make ps         # ดูสถานะ
make psql       # เข้า psql ของฐานข้อมูลเครื่องเดฟ
make sh         # เข้า shell ของคอนเทนเนอร์ app
make migrate    # สั่งรัน migration เอง
make smoke      # ทดสอบทั้งวงจร
make down       # หยุด (ข้อมูลยังอยู่)
make reset      # ล้างฐานข้อมูลเดฟแล้วเริ่มใหม่ (ถามยืนยันก่อน)
make config     # ตรวจไวยากรณ์ไฟล์ compose ทั้งสามชุด
```

---

## ตัวแปรที่ต้องรู้จัก

| ตัวแปร | เครื่องเดฟ | production | หมายเหตุ |
|---|---|---|---|
| `DB_HOST` | `db` | IP วงภายในของเครื่องฐานข้อมูล | **ตัวแปรเดียวที่ทำให้สองแบบต่างกันจริง ๆ** |
| `DB_SSLMODE` | `disable` | `require` | prod วิ่งข้ามเครื่อง ต้องเข้ารหัสเสมอ |
| `POSTGRES_PASSWORD` | `devpassword` | ต้องกำหนดเอง | ฝั่ง web กับ db ต้องตรงกัน |
| `WEB_PORT` / `HTTP_PORT` | `8080` | `80` | พอร์ตที่เปิดออกนอกเครื่อง |
| `DB_BIND_ADDRESS` | — | IP วงภายในของเครื่อง db | **ห้ามใส่ `0.0.0.0`** |
| `RUN_MIGRATIONS` | `true` | `true` | ตั้ง `false` ถ้าทีมอยากสั่ง migration เอง |

ตัวแปรของ production ที่เขียนเป็น `${VAR:?...}` ใน compose คือ **บังคับ** — ถ้าลืมใส่ compose จะไม่ยอมสตาร์ตพร้อมบอกชื่อตัวแปรที่ขาด ดีกว่าขึ้นไปแล้วไปพังตอนมีผู้ใช้จริง

---

## deploy ขึ้น production

ครั้งแรกอ่าน [docs/DEPLOY.md](docs/DEPLOY.md) ให้จบ (มีเรื่องไฟร์วอลล์และใบรับรองที่ต้องทำก่อน) หลังจากตั้งค่าครั้งแรกเสร็จแล้ว การ deploy รอบถัดไปเหลือแค่:

```bash
cp deploy/deploy.env.example deploy/deploy.env   # ทำครั้งเดียว แก้ IP ของสองเครื่อง
make deploy-db      # เครื่องฐานข้อมูลก่อนเสมอ
make deploy-web     # แล้วค่อยเครื่อง web
```

สคริปต์จะ `rsync` ไฟล์ขึ้นไป แล้ว `ssh` เข้าไปสั่ง `docker compose up -d --build` ให้เอง โดย:

- **ไม่แตะไฟล์ `.env` บนเครื่องปลายทาง** (ค่าของแต่ละเครื่องเป็นของเครื่องนั้น)
- ถ้าเครื่องปลายทางยังไม่มี `.env` จะคัดลอกไฟล์ตัวอย่างไปให้แล้วหยุด เพื่อให้ไปกรอกค่าก่อน
- จบด้วยการเรียก `/readyz` เพื่อยืนยันว่า app ต่อฐานข้อมูลได้จริง ไม่ใช่แค่คอนเทนเนอร์ขึ้น

---

## ความปลอดภัยที่ทำไว้ให้แล้ว

- ฐานข้อมูลบน production ผูกกับ **IP วงภายในเท่านั้น** (`DB_BIND_ADDRESS`) ไม่ใช่ `0.0.0.0`
- `pg_hba.conf` บังคับ `hostssl` + `scram-sha-256` และ **ปฏิเสธ** การต่อแบบไม่เข้ารหัสทิ้งทันที
- คอนเทนเนอร์ `app` บน production รันด้วย user `node` ไม่ใช่ root
- `app` ไม่เปิดพอร์ตออกนอกเครื่องเลย เข้าได้ทางเดียวคือผ่าน nginx
- log ถูกจำกัดขนาด (`max-size: 10m`, `max-file: 5`) ไม่ให้ดิสก์เต็ม — **อย่าใช้ logrotate กับ log ของ docker** เพราะ `copytruncate` จะทำให้ `docker logs` ค้าง
- ฐานข้อมูลถูก `pg_dump` อัตโนมัติวันละครั้ง เก็บย้อนหลัง 7 วัน

สิ่งที่ **ยังต้องทำเองตามสภาพแวดล้อมจริง**: เปิด HTTPS ที่ nginx (ดู `nginx/conf.d/prod-tls.conf.example`), ตั้งไฟร์วอลล์ให้เฉพาะเครื่อง web ต่อพอร์ต 5432 ได้ และย้ายไฟล์ backup ออกไปเก็บนอกเครื่อง

---

## ปัญหาที่เจอบ่อย

ดู [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — รวมกับดักที่เสียเวลากันบ่อย เช่น

- `pg_isready` ตอบ healthy ตั้งแต่พอร์ตยังไม่เปิด (ต้องใส่ `-h 127.0.0.1`)
- PostgreSQL 18 ต้อง mount volume ที่ `/var/lib/postgresql` ไม่ใช่ `/var/lib/postgresql/data`
- nginx ดับตอนสตาร์ตเพราะ resolve ชื่อ `app` ไม่ได้ (`host not found in upstream`)
- แก้ไฟล์ใน `db/init/` แล้วไม่มีอะไรเกิดขึ้น เพราะมันรันครั้งเดียวตอนฐานข้อมูลยังว่าง

---

## ขอบเขตของตัวอย่างนี้

ตัวอย่างนี้ตั้งใจให้ครบพอจะเอาไปต่อยอดได้จริง แต่ยังไม่ได้ทำ: HTTPS ที่ออกใบรับรองอัตโนมัติ, การรัน app หลายตัวพร้อมกัน (scale), replication ของฐานข้อมูล และการส่ง log ออกไปเก็บที่ระบบกลาง
