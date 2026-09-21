# db/certs

ใบรับรอง TLS ของ PostgreSQL บนเครื่องฐานข้อมูล production

สร้างด้วย:

```bash
./deploy/gen-db-certs.sh 10.0.0.20      # ใส่ IP วงภายในของเครื่องฐานข้อมูล
```

จะได้ไฟล์ `server.crt` และ `server.key` ซึ่ง **ไม่ถูก commit ขึ้น git** (ดู `.gitignore` ในโฟลเดอร์นี้)
โฟลเดอร์นี้ถูก mount เข้าคอนเทนเนอร์ที่ `/certs` แล้วคอนเทนเนอร์จะคัดลอกไปตั้งสิทธิ์ 600 ให้เอง
