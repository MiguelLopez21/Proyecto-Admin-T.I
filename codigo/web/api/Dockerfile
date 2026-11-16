FROM node:20-alpine

WORKDIR /app
ENV NODE_ENV=production

# Dependencias primero (capa cacheada), con versiones fijas del package-lock.json
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY src ./src
COPY db ./db

USER node
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/api/health >/dev/null || exit 1

CMD ["node", "src/server.js"]
