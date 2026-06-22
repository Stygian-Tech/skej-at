# syntax=docker/dockerfile:1
# Build context: services/skej-api.
# This also tolerates a repo-root context for local/CI builds.

FROM swift:6.2-jammy AS build
WORKDIR /build

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git config --global --add safe.directory '*'
ENV GIT_TERMINAL_PROMPT=0

COPY . /build/source

RUN --mount=type=cache,target=/root/.cache \
    set -eux; \
    if [ -f /build/source/services/skej-api/Package.swift ]; then \
        package_dir=/build/source/services/skej-api; \
    else \
        package_dir=/build/source; \
    fi; \
    cd "$package_dir"; \
    swift package resolve; \
    swift build -c release --product SkejAPI; \
    install -m 0755 .build/release/SkejAPI /build/SkejAPI

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
