# ============================================================================
#  ทางลัดของคำสั่งที่ใช้บ่อย — พิมพ์ `make` เฉย ๆ เพื่อดูรายการทั้งหมด
#  ทุก target คือ docker compose ธรรมดา ไม่มีเวทมนตร์อะไรซ่อนอยู่
# ============================================================================
DEV      := docker compose -f compose.yaml -f compose.dev.yaml
PROD_WEB := docker compose -f compose.yaml -f compose.prod.web.yaml
PROD_DB  := docker compose -f compose.prod.db.yaml

WEB_PORT ?= 8080

.DEFAULT_GOAL := help
.PHONY: help dev up build down logs ps sh psql migrate smoke reset config \
        prod-web-up prod-web-down prod-web-logs prod-db-up prod-db-down prod-db-logs \
        deploy-web deploy-db certs

help:  ## แสดงคำสั่งทั้งหมด
	@echo "คำสั่งที่ใช้ได้:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# ---------- เครื่องเดฟ ----------
dev:  ## สตาร์ตทั้ง stack บนเครื่องเดฟ แล้วค้าง log ไว้ดู (Ctrl+C เพื่อหยุด)
	$(DEV) up --build

up:  ## สตาร์ตเครื่องเดฟแบบทำงานเบื้องหลัง
	$(DEV) up -d --build
	@echo "เปิด http://localhost:$(WEB_PORT)"

build:  ## build image ใหม่โดยไม่ใช้ cache
	$(DEV) build --no-cache

down:  ## หยุดทุก container (ข้อมูลใน volume ยังอยู่)
	$(DEV) down

logs:  ## ดู log แบบไหลต่อเนื่อง
	$(DEV) logs -f --tail=100

ps:  ## ดูสถานะ container
	$(DEV) ps

sh:  ## เข้า shell ในคอนเทนเนอร์ app
	$(DEV) exec app sh

psql:  ## เปิด psql ต่อฐานข้อมูลของเครื่องเดฟ
	$(DEV) exec db psql -U $${POSTGRES_USER:-appuser} -d $${POSTGRES_DB:-appdb}

migrate:  ## สั่งรัน migration เอง (ปกติ app รันให้ตอนสตาร์ตอยู่แล้ว)
	$(DEV) exec app npm run migrate

smoke:  ## ยิงทดสอบว่า nginx + app + db ต่อกันติดจริง
	@./deploy/smoke-test.sh http://localhost:$(WEB_PORT)

reset:  ## ล้างฐานข้อมูลเครื่องเดฟทิ้งแล้วเริ่มใหม่ (ข้อมูลหายหมด)
	@printf "จะลบ volume ฐานข้อมูลของเครื่องเดฟทิ้ง แน่ใจหรือไม่? [y/N] " && read ans && [ "$$ans" = "y" ]
	$(DEV) down -v
	$(DEV) up -d --build

config:  ## ตรวจไวยากรณ์ compose ทั้งสามชุด
	@echo "== dev ==" && $(DEV) config -q && echo "ผ่าน"
	@echo "== prod web ==" && DB_HOST=x POSTGRES_DB=x POSTGRES_USER=x POSTGRES_PASSWORD=x $(PROD_WEB) config -q && echo "ผ่าน"
	@echo "== prod db ==" && DB_BIND_ADDRESS=127.0.0.1 POSTGRES_DB=x POSTGRES_USER=x POSTGRES_PASSWORD=x $(PROD_DB) config -q && echo "ผ่าน"

# ---------- รันบนเครื่อง production (ssh เข้าไปแล้วค่อยใช้) ----------
prod-web-up:  ## [บนเครื่อง web] สตาร์ต nginx + app
	$(PROD_WEB) up -d --build --remove-orphans

prod-web-down:  ## [บนเครื่อง web] หยุด nginx + app
	$(PROD_WEB) down

prod-web-logs:  ## [บนเครื่อง web] ดู log
	$(PROD_WEB) logs -f --tail=100

prod-db-up:  ## [บนเครื่อง db] สตาร์ต postgres + backup
	$(PROD_DB) up -d --remove-orphans

prod-db-down:  ## [บนเครื่อง db] หยุด postgres + backup
	$(PROD_DB) down

prod-db-logs:  ## [บนเครื่อง db] ดู log
	$(PROD_DB) logs -f --tail=100

# ---------- สั่งจากเครื่องเดฟ ----------
certs:  ## สร้างใบรับรอง TLS ให้เครื่องฐานข้อมูล
	./deploy/gen-db-certs.sh

deploy-db:  ## deploy ขึ้นเครื่องฐานข้อมูล (ทำก่อนเสมอ)
	./deploy/deploy-db.sh

deploy-web:  ## deploy ขึ้นเครื่อง web
	./deploy/deploy-web.sh
