# syntax=docker/dockerfile:1

FROM oven/bun:1.3.14 AS dependencies
WORKDIR /app

COPY package.json bun.lock turbo.json ./
COPY apps/web/package.json apps/web/package.json
COPY packages/lexicons/package.json packages/lexicons/package.json
RUN bun install --frozen-lockfile

FROM dependencies AS build
COPY apps/web apps/web
COPY packages/lexicons packages/lexicons

ARG APP_ENV
ARG NEXT_PUBLIC_APP_ENV
ARG NEXT_PUBLIC_SITE_URL
ARG SKEJ_API_URL
ENV APP_ENV=$APP_ENV
ENV NEXT_PUBLIC_APP_ENV=$NEXT_PUBLIC_APP_ENV
ENV NEXT_PUBLIC_SITE_URL=$NEXT_PUBLIC_SITE_URL
ENV SKEJ_API_URL=$SKEJ_API_URL

RUN bun run --cwd apps/web build

FROM oven/bun:1.3.14 AS runtime
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

COPY --from=build /app/apps/web/.next/standalone ./
COPY --from=build /app/apps/web/.next/static ./apps/web/.next/static
COPY --from=build /app/apps/web/public ./apps/web/public

EXPOSE 3000
USER bun
CMD ["bun", "apps/web/server.js"]
