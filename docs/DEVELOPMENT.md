# งานประจำวันของทีมเดฟ

## สตาร์ตงาน

```bash
make dev        # ค้าง log ไว้ดู กด Ctrl+C เพื่อหยุด
# หรือ
make up         # ทำงานเบื้องหลัง แล้วค่อย make logs
```

เข้า <http://localhost:8080>

แก้ไฟล์ใน `app/src/` แล้ว **ไม่ต้อง build ใหม่** — `compose.dev.yaml` mount โฟลเดอร์นั้นเข้าไป
และ `node --watch` รีสตาร์ตให้เอง (เห็นใน log ว่า `Restarting 'src/server.js'`)

## เมื่อไหร่ต้อง build image ใหม่

| แก้อะไร | ต้องทำอะไร |
|---|---|
| ไฟล์ใน `app/src/` | ไม่ต้องทำอะไร รีโหลดเอง |
| ไฟล์ใน `app/migrations/` | ไม่ต้องทำอะไร (mount ไว้) แต่ migration รันตอนสตาร์ต จึงควร `make down && make up` |
| ไฟล์ใน `app/public/` | กด refresh บนเบราว์เซอร์ (nginx mount โฟลเดอร์นี้อยู่) |
| `package.json` (เพิ่ม/ลบ lib) | `make up` (compose จะ build ใหม่ให้) |
| `Dockerfile` | `make up` |
| `nginx/conf.d/dev.conf` | `docker compose -f compose.yaml -f compose.dev.yaml restart nginx` |
| ไฟล์ compose | `make up` |

## เพิ่ม dependency

```bash
# เพิ่มใน package.json และอัปเดต lockfile (ต้องมี node ในเครื่อง)
cd app && npm install ชื่อแพ็กเกจ --package-lock-only && cd ..
make up
```

ถ้าในเครื่องไม่มี Node ให้สั่งผ่านคอนเทนเนอร์:

```bash
docker run --rm -v "$PWD/app:/app" -w /app node:22-alpine \
  npm install ชื่อแพ็กเกจ --package-lock-only
make up
```

> ต้อง commit `package-lock.json` ทุกครั้ง เพราะ `Dockerfile` ใช้ `npm ci` ซึ่งติดตั้งตามล็อกไฟล์เป๊ะ ๆ
> ทำให้ image ที่ build วันนี้กับเดือนหน้าได้ของเหมือนกัน

## เปลี่ยนโครงสร้างฐานข้อมูล

**อย่าแก้ไฟล์ใน `db/init/`** — ไฟล์พวกนั้นรันแค่ครั้งเดียวตอนฐานข้อมูลยังว่าง

สร้างไฟล์ใหม่ใน `app/migrations/` ตั้งชื่อให้เรียงต่อจากของเดิม:

```bash
cat > app/migrations/0003_add_author_to_messages.sql <<'SQL'
alter table messages add column if not exists author text;
create index if not exists messages_author_idx on messages (author);
SQL

make down && make up    # migration จะรันตอน app สตาร์ต
# หรือสั่งเองโดยไม่ต้องรีสตาร์ต:
make migrate
```

กติกาที่ทีมควรถือร่วมกัน:

- เขียนให้ **รันซ้ำได้** (`if not exists`, `if exists`) เผื่อกรณีรันค้างกลางทาง
- **หนึ่งไฟล์ต่อหนึ่งการเปลี่ยนแปลง** และไม่แก้ไฟล์ที่เคยรันบน production ไปแล้ว
  ถ้าแก้ไฟล์เก่า ฐานข้อมูลที่รันไปแล้วจะไม่รันซ้ำให้ (ตาราง `schema_migrations` จำชื่อไฟล์ไว้)
- migration ที่ลบคอลัมน์หรือตาราง ให้แยกเป็นคนละรอบ deploy กับโค้ดที่เลิกใช้มัน
  ไม่งั้นช่วงที่คอนเทนเนอร์เก่ายังไม่ตาย โค้ดเก่าจะวิ่งชนโครงสร้างใหม่

ดูว่ารันอะไรไปแล้วบ้าง:

```bash
make psql
appdb=# select * from schema_migrations order by filename;
```

## เข้าไปดูฐานข้อมูล

```bash
make psql                                   # psql ในคอนเทนเนอร์
```

หรือต่อจากเครื่องตัวเองด้วย DBeaver / TablePlus:

```
host     127.0.0.1
port     5432        (หรือค่า DB_PORT_HOST ที่ตั้งไว้)
database appdb
user     appuser
password devpassword
```

## ดีบัก

ยิง API ตรงโดยไม่ผ่าน nginx (ช่วยแยกว่าปัญหาอยู่ที่ nginx หรือที่แอป):

```bash
curl -s localhost:3000/readyz | python3 -m json.tool     # ตรงไปที่ app
curl -s localhost:8080/readyz | python3 -m json.tool     # ผ่าน nginx
```

เข้าไปดูข้างในคอนเทนเนอร์:

```bash
make sh
# ในคอนเทนเนอร์:
env | grep DB_          # ดูว่า env ที่แอปเห็นจริง ๆ คืออะไร
wget -qO- localhost:3000/healthz
```

ดู log แยกทีละตัว:

```bash
docker compose -f compose.yaml -f compose.dev.yaml logs -f app
docker compose -f compose.yaml -f compose.dev.yaml logs -f nginx
docker compose -f compose.yaml -f compose.dev.yaml logs -f db
```

## ล้างเครื่องเริ่มใหม่

```bash
make reset      # ลบ volume ฐานข้อมูลแล้วสตาร์ตใหม่ (ถามยืนยันก่อน)
```

## ก่อนเปิด pull request

```bash
make config     # ไฟล์ compose ทั้งสามชุดต้องผ่าน
make up
make smoke      # ทุกข้อต้องผ่าน
```

## เพิ่ม service ใหม่ (เช่น Redis)

1. เพิ่มใน `compose.dev.yaml` เพื่อใช้บนเครื่องเดฟก่อน:

   ```yaml
   redis:
     image: redis:7-alpine
     ports:
       - "127.0.0.1:${REDIS_PORT_HOST:-6379}:6379"
     healthcheck:
       test: ["CMD", "redis-cli", "ping"]
       interval: 5s
     networks: [web]
   ```

2. เพิ่ม env ที่แอปต้องใช้ใน `compose.yaml` (ให้มี default ที่ dev ใช้ได้ทันที)
3. ตัดสินใจว่า production จะวางไว้เครื่องไหน
   - อยู่เครื่องเดียวกับ web → เพิ่มใน `compose.prod.web.yaml`
   - แยกเครื่อง → ทำไฟล์ `compose.prod.redis.yaml` ตามแบบของ `compose.prod.db.yaml` (ผูกพอร์ตกับ IP วงภายใน + ตั้งรหัสผ่าน)
4. อัปเดต `env/*.env.example` และ README ให้ทีมรู้ว่ามีตัวแปรใหม่
