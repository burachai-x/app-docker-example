// รวมการอ่าน env ไว้ที่เดียว เพื่อให้เห็นชัดว่า dev กับ prod ต่างกันแค่ "ค่า" ไม่ใช่ "โค้ด"
const required = (name) => {
  const value = process.env[name];
  if (!value) {
    throw new Error(`ไม่ได้กำหนดตัวแปร ${name} — ดูไฟล์ env/*.env.example`);
  }
  return value;
};

export const config = {
  env: process.env.NODE_ENV ?? 'development',
  port: Number(process.env.PORT ?? 3000),
  db: {
    host: process.env.DB_HOST ?? 'db',
    port: Number(process.env.DB_PORT ?? 5432),
    database: process.env.DB_NAME ?? 'appdb',
    user: process.env.DB_USER ?? 'appuser',
    password: required('DB_PASSWORD'),
    // disable = dev ในเครื่องเดียวกัน, require = prod ที่วิ่งข้ามเครื่อง
    sslmode: process.env.DB_SSLMODE ?? 'disable',
  },
  // ปิด migration อัตโนมัติได้ ถ้าทีมอยากสั่งเองตอน deploy
  runMigrationsOnBoot: (process.env.RUN_MIGRATIONS ?? 'true') !== 'false',
};
