import express from 'express';
import { config } from './config.js';
import { pool, ping } from './db.js';
import { migrate } from './migrate.js';

const app = express();
app.use(express.json());

// nginx อยู่หน้าเสมอ จึงต้องเชื่อ X-Forwarded-* เพื่อให้ req.ip เป็น IP ของผู้ใช้จริง
app.set('trust proxy', 1);

// liveness: ตอบได้แม้ DB ล่ม — ใช้บอกว่า "process ยังไหว ไม่ต้อง restart"
app.get('/healthz', (_req, res) => {
  res.json({ status: 'ok', env: config.env, uptime: Math.round(process.uptime()) });
});

// readiness: แตะ DB จริง — ใช้บอกว่า "พร้อมรับทราฟฟิกไหม"
app.get('/readyz', async (_req, res) => {
  try {
    const row = await ping();
    res.json({
      status: 'ready',
      db: { host: config.db.host, sslmode: config.db.sslmode, now: row.now },
    });
  } catch (err) {
    res.status(503).json({ status: 'not-ready', error: err.message });
  }
});

app.get('/api/messages', async (_req, res, next) => {
  try {
    const { rows } = await pool.query(
      'select id, body, created_at from messages order by id desc limit 50',
    );
    res.json(rows);
  } catch (err) {
    next(err);
  }
});

app.post('/api/messages', async (req, res, next) => {
  const body = (req.body?.body ?? '').trim();
  if (!body) {
    return res.status(400).json({ error: 'ต้องส่งฟิลด์ body' });
  }
  try {
    const { rows } = await pool.query(
      'insert into messages (body) values ($1) returning id, body, created_at',
      [body],
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    next(err);
  }
});

app.use((err, _req, res, _next) => {
  console.error('[http]', err.message);
  res.status(500).json({ error: config.env === 'production' ? 'internal error' : err.message });
});

const start = async () => {
  if (config.runMigrationsOnBoot) {
    await migrate();
  }
  const server = app.listen(config.port, '0.0.0.0', () => {
    console.log(`[app] listening on :${config.port} (env=${config.env}, db=${config.db.host})`);
  });

  // ปิดให้เรียบร้อยเมื่อ docker ส่ง SIGTERM ไม่งั้น request ที่ค้างอยู่จะถูกตัดกลางคัน
  const shutdown = (signal) => async () => {
    console.log(`[app] ได้รับ ${signal} — กำลังปิด`);
    server.close(async () => {
      await pool.end();
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 10_000).unref();
  };
  process.on('SIGTERM', shutdown('SIGTERM'));
  process.on('SIGINT', shutdown('SIGINT'));
};

start().catch((err) => {
  console.error('[app] สตาร์ตไม่สำเร็จ:', err.message);
  process.exit(1);
});
