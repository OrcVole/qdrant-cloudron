# Qdrant packaged for Cloudron.
#
# The single source of truth for the upstream version is the QDRANT_VERSION build argument
# below. The Cloudron manifest mirrors it in `upstreamVersion`; nothing else hardcodes it.
# See docs/UPGRADING.md before changing it (the storage-format and linkage gates apply).
#
# Qdrant ships as a single dynamically linked binary built on Debian bookworm, which requires
# glibc >= 2.36. cloudron/base:5.0.0 provides glibc 2.39, which satisfies it. The match is
# looser than a Chainguard build, but every version bump must still re-run the linkage gate
# (docs/RELEASING.md), because a future Qdrant build could raise the glibc floor and would
# then fail at runtime on this base, not at build time.

ARG QDRANT_VERSION=v1.18.2

# --- Stage 1: the official upstream image, used only as a source for the binary and assets --
# Pinned by digest (resolved 2026-06-25). Tag v1.18.2 resolves to this digest.
FROM qdrant/qdrant:v1.18.2@sha256:75eab8c4ba42096724fdcfde8b4de0b5713d529dde32f285a1f86fdcb2c9e50c AS upstream

# --- Stage 2: the Cloudron app image -------------------------------------------------------
# The final stage must be this exact base so the Cloudron file manager, web terminal, and log
# viewer work. Tag 5.0.0 resolves to this digest (Ubuntu 24.04, glibc 2.39).
FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c

# cloudron/base:5.0.0 already provides gosu, Node.js, curl, tini, ca-certificates, coreutils,
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
# base 5.0.0 (glibc 2.39); it guards against a future base downgrade or an upstream toolchain
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
