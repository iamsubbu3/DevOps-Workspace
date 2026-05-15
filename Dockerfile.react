# ==============================
# STAGE 1 — BUILD STAGE
# ==============================
FROM node:20-alpine AS builder

# Set working directory
WORKDIR /app

# Install dependencies first (better layer caching)
COPY package*.json ./

# Install ALL deps (needed for build if TS/webpack/etc)
RUN npm ci && npm cache clean --force

# Copy source code
COPY . .

# Build step (uncomment if using TypeScript / build step)
RUN npm run build


# ==============================
# STAGE 2 — PRODUCTION IMAGE
# ==============================
FROM nginx:stable-alpine

# Copy custom nginx config (React router support)
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy React build files from builder stage
COPY --from=builder /app/build /usr/share/nginx/html

# Expose nginx port
EXPOSE 80

# Healthcheck (adjust endpoint)
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost/ || exit 1

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
