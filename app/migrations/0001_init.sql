create table if not exists messages (
  id          bigserial primary key,
  body        text        not null,
  created_at  timestamptz not null default now()
);

create index if not exists messages_created_at_idx on messages (created_at desc);
