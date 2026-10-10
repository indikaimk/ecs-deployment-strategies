# Multi-stage production Dockerfile optimized for AWS Graviton (linux/arm64)
# Compatible with multi-arch builds via docker buildx

# --- Stage 1: Dependencies ---
FROM node:20-alpine AS dependencies
WORKDIR /app

# Install build dependencies if needed
COPY package.json package-lock.json ./
RUN npm ci --only=production --ignore-scripts

# --- Stage 2: Final Runtime ---
FROM node:20-alpine AS runner
WORKDIR /app

# Install dumb-init for proper PID 1 signal forwarding (SIGTERM / SIGINT)
# Critical for ECS Fargate graceful connection draining
RUN apk add --no-cache dumb-init

ENV NODE_ENV=production
ENV PORT=3000
ENV APP_VERSION=v1.0.0
ENV APP_COLOR=blue
ENV APP_RELEASE_TITLE="Blue Release"

# Create and switch to non-root user (built into node:alpine)
USER node

# Copy production dependencies and application files
COPY --chown=node:node --from=dependencies /app/node_modules ./node_modules
COPY --chown=node:node package.json ./
COPY --chown=node:node src/ ./src/

EXPOSE 3000

# Docker container healthcheck
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "src/server.js"]
