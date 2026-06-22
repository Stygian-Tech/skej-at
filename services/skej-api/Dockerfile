# syntax=docker/dockerfile:1
# Build context: repo root.

FROM swift:6.2-jammy AS build
WORKDIR /build

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git config --global --add safe.directory '*'
ENV GIT_TERMINAL_PROMPT=0

COPY services/skej-api/Package.swift services/skej-api/Package.resolved* services/skej-api/

WORKDIR /build/services/skej-api
RUN --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/build/services/skej-api/.build \
    swift package resolve

WORKDIR /build
COPY services/skej-api/Sources services/skej-api/Sources
COPY services/skej-api/Tests services/skej-api/Tests

WORKDIR /build/services/skej-api
RUN --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/build/services/skej-api/.build \
    swift build -c release --product SkejAPI \
    && install -m 0755 /build/services/skej-api/.build/release/SkejAPI /build/SkejAPI

FROM swift:6.2-jammy

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl libsqlite3-0 \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /build/SkejAPI /app/SkejAPI

RUN mkdir -p /var/lib/skej-api/data \
    && chown -R nobody:nogroup /var/lib/skej-api

ENV PORT=8080
ENV SKEJ_SQLITE_PATH=/var/lib/skej-api/data/skej.sqlite
EXPOSE 8080
USER nobody
ENTRYPOINT ["/app/SkejAPI"]
