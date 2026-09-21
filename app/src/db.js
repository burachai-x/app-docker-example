import pg from 'pg';
import { config } from './config.js';

// sslmode=require คือ "เข้ารหัสแต่ไม่ตรวจใบรับรอง" เหมาะกับ self-signed cert ระหว่างเครื่องในวงเดียวกัน
// ถ้าต้องการตรวจ CA ด้วย ให้ตั้ง DB_SSLMODE=verify-full แล้วส่ง DB_SSL_CA มาเป็น path ของไฟล์ CA
const sslOption = () => {
  if (config.db.sslmode === 'disable') return false;
  if (config.db.sslmode === 'verify-full') {
    return {
      rejectUnauthorized: true,
      ca: process.env.DB_SSL_CA_CONTENT,
      servername: config.db.host,
    };
  }
  return { rejectUnauthorized: false };
};

export const pool = new pg.Pool({
  host: config.db.host,
  port: config.db.port,
  database: config.db.database,
  user: config.db.user,
  password: config.db.password,
  ssl: sslOption(),
  max: Number(process.env.DB_POOL_MAX ?? 10),
  connectionTimeoutMillis: 5000,
  idleTimeoutMillis: 30000,
});

pool.on('error', (err) => {
  console.error('[db] connection pool error:', err.message);
});

export const ping = async () => {
  const { rows } = await pool.query('select now() as now, version() as version');
  return rows[0];
};
