# Qdrant packaged for Cloudron.
#
# The single source of truth for the upstream version is the QDRANT_VERSION build argument
# below. The Cloudron manifest mirrors it in `upstreamVersion`; nothing else hardcodes it.
# See docs/UPGRADING.md before changing it (the storage-format and linkage gates apply).
#
# Qdrant ships as a single dynamically linked binary built on Debian bookworm, which requires
# glibc >= 2.36. cloudron/base:6.0.1 provides glibc 2.43, which satisfies it. The match is
# looser than a Chainguard build, but every version bump must still re-run the linkage gate
# (docs/RELEASING.md), because a future Qdrant build could raise the glibc floor and would
# then fail at runtime on this base, not at build time.

ARG QDRANT_VERSION=v1.20.0

# --- Stage 1: the official upstream image, used only as a source for the binary and assets --
# Pinned by digest (resolved 2026-10-31). Tag v1.20.0 resolves to this digest.
FROM docker.io/qdrant/qdrant:v1.20.0@sha256:9bfc89f9914fc14876a88c05270685921a55b8877b254a98bcc1cc2f0a424cd2 AS upstream

# --- Stage 2: the Cloudron app image -------------------------------------------------------
# The final stage must be this exact base so the Cloudron file manager, web terminal, and log
# viewer work. Tag 6.0.1 resolves to this digest (Ubuntu 26.04, glibc 2.43).
FROM docker.io/cloudron/base:6.0.1@sha256:7b1e729960c3ca312d26e886917ba89483241bba0219ff292858e10d9d5768ee

# cloudron/base:6.0.1 already provides gosu, jq, curl, tini, ca-certificates, coreutils,
# and openssl. Qdrant needs no extra runtime tools: it is a single binary, and its dashboard
# operates the database through the API rather than rewriting the server config file, so
# unlike some packages this one needs no YAML-rewriting helper at boot.

# Qdrant binary, the dashboard single-page app, and the upstream default config. WORKDIR is
# /app/code (set below) so Qdrant resolves ./static (the dashboard) and ./config/config.yaml.
COPY --from=upstream /qdrant/qdrant /app/code/qdrant
COPY --from=upstream /qdrant/static /app/code/static
COPY --from=upstream /qdrant/config/config.yaml /app/code/config/config.yaml

# Package entrypoint, the seed config template, and the opt-in snapshot cron task.
COPY start.sh /app/code/start.sh
COPY snapshot.sh /app/code/snapshot.sh
COPY config/production.yaml.template /app/code/config/production.yaml.template
RUN chmod 0755 /app/code/qdrant /app/code/start.sh /app/code/snapshot.sh

# Record the pinned upstream version in the image for debuggability and log output.
ARG QDRANT_VERSION
ENV QDRANT_VERSION=${QDRANT_VERSION}

# Linkage gate (Gate 1, docs/RELEASING.md): fail the BUILD if the binary cannot resolve its
# shared libraries or its required glibc on this base, and confirm it executes. This passes on
# base 6.0.1 (glibc 2.43); it guards against a future base downgrade or an upstream toolchain
# bump that raises the glibc floor.
RUN set -eux; \
    ldd /app/code/qdrant; \
    if ldd /app/code/qdrant 2>&1 | grep -qE 'not found'; then \
      echo "FATAL: unresolved shared library or glibc symbol on this base"; exit 1; \
    fi; \
    /app/code/qdrant --version

LABEL org.opencontainers.image.title="qdrant-cloudron" \
      org.opencontainers.image.description="Qdrant vector database packaged for Cloudron" \
      org.opencontainers.image.licenses="Apache-2.0"

WORKDIR /app/code

# start.sh runs as root, prepares /app/data, then drops to the cloudron user via gosu.
CMD [ "/app/code/start.sh" ]
