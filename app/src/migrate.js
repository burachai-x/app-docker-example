// Migration แบบเล็กที่สุดที่ใช้งานจริงได้: ไล่ไฟล์ .sql ใน migrations/ ตามชื่อ แล้วจำว่ารันอะไรไปแล้ว
// ใช้ advisory lock กันกรณี app หลาย container สตาร์ตพร้อมกันแล้วแย่งกันรัน
import { readdir, readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from './db.js';

const MIGRATIONS_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'migrations');
const LOCK_ID = 4242; // ตัวเลขอะไรก็ได้ ขอแค่ทุก instance ใช้ค่าเดียวกัน

export const migrate = async () => {
  const client = await pool.connect();
  try {
    await client.query('select pg_advisory_lock($1)', [LOCK_ID]);
    await client.query(`
      create table if not exists schema_migrations (
        filename    text primary key,
        applied_at  timestamptz not null default now()
      )
    `);

    const { rows } = await client.query('select filename from schema_migrations');
    const applied = new Set(rows.map((r) => r.filename));

    const files = (await readdir(MIGRATIONS_DIR))
      .filter((f) => f.endsWith('.sql'))
      .sort();

    for (const file of files) {
      if (applied.has(file)) continue;
      const sql = await readFile(join(MIGRATIONS_DIR, file), 'utf8');
      console.log(`[migrate] apply ${file}`);
      await client.query('begin');
      try {
        await client.query(sql);
        await client.query('insert into schema_migrations (filename) values ($1)', [file]);
        await client.query('commit');
      } catch (err) {
        await client.query('rollback');
        throw new Error(`migration ${file} ล้มเหลว: ${err.message}`);
      }
    }
    console.log(`[migrate] เรียบร้อย (${files.length} ไฟล์, ใหม่ ${files.length - applied.size} ไฟล์)`);
  } finally {
    await client.query('select pg_advisory_unlock($1)', [LOCK_ID]).catch(() => {});
    client.release();
  }
};

// เรียกตรงจาก CLI ได้: npm run migrate
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  migrate()
    .then(() => pool.end())
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('[migrate]', err.message);
      process.exit(1);
    });
}
