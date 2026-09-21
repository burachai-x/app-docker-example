-- ข้อมูลตัวอย่างไว้ให้เห็นผลทันทีตอนเปิดหน้าเว็บครั้งแรก
insert into messages (body)
select 'สวัสดีจาก migration 0002'
where not exists (select 1 from messages);
