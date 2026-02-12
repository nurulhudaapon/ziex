FROM oven/bun:1 as base
WORKDIR /usr/src/app

FROM base AS install
RUN mkdir -p /temp/dev
COPY package.json bun.lockb* /temp/dev/
RUN cd /temp/dev && bun install --frozen-lockfile || bun install

RUN mkdir -p /temp/prod
COPY package.json bun.lockb* /temp/prod/
RUN cd /temp/prod && bun install --frozen-lockfile --production || bun install --production

FROM base AS builder
COPY --from=install /temp/dev/node_modules node_modules
COPY . .

ENV NODE_ENV=production
RUN bun run build

FROM base AS release

# Install curl for health checks
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

COPY --from=install /temp/prod/node_modules node_modules
COPY --from=builder /usr/src/app/bun.lockb* ./
COPY --from=builder /usr/src/app/package.json ./
COPY --from=builder /usr/src/app/.output ./.output

USER bun
EXPOSE 3000

ENV NODE_ENV=production
ENV PORT 3000
ENV HOST "0.0.0.0"

ENTRYPOINT ["bun", "run", "start"]
