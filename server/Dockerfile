# ── Build stage ───────────────────────────────────────────────────────────
FROM node:20-slim AS build
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci
COPY . .
RUN npm run build

# ── Runtime stage ─────────────────────────────────────────────────────────
FROM node:20-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev
COPY --from=build /app/dist ./dist
COPY --from=build /app/supabase ./supabase

# Drop root.
#
# The container was running as uid 0, so a remote-code-execution bug anywhere in
# the dependency tree would have owned the whole container rather than one
# unprivileged process. `node` is a non-root user the base image already
# provides, so this costs nothing. The chown covers the files copied in above,
# which are owned by root from the build stage.
RUN chown -R node:node /app
USER node

EXPOSE 8080
CMD ["node", "dist/server.js"]
