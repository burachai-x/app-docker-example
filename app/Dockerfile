# syntax=docker/dockerfile:1
# ใช้ไฟล์เดียวทั้ง dev และ prod ต่างกันแค่ --target ที่ compose สั่ง
ARG NODE_VERSION=22

FROM node:${NODE_VERSION}-alpine AS base
ENV NODE_ENV=production
WORKDIR /app
# ติดตั้ง dependency ก่อน copy source เพื่อให้ layer นี้ถูก cache ไว้ตอนแก้โค้ด
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

# ---- dev: source ถูก mount ทับจาก compose แล้วใช้ node --watch รีโหลดเอง ----
FROM base AS dev
ENV NODE_ENV=development
COPY . .
EXPOSE 3000
CMD ["npm", "run", "dev"]

# ---- prod: โค้ดฝังอยู่ใน image, รันด้วย user node ที่ไม่ใช่ root ----
FROM base AS prod
COPY --chown=node:node . .
USER node
EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/healthz >/dev/null || exit 1
CMD ["node", "src/server.js"]
