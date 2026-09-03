# Streamline Playground Image
#
# IMPORTANT: like the official `Dockerfile`, the build context here is the
# prepared *Streamline core* checkout, not this repository. streamline-deploy
# contains no Rust sources, so this image cannot be built from the repository
# root.
#
# Build:
#   scripts/prepare-core-context.sh                  # -> .build/core
#   docker build -f playground/Dockerfile .build/core \
#     --build-arg STREAMLINE_CORE_REF="$(scripts/prepare-core-context.sh --print-ref)" \
#     -t streamline-playground:dev
#
# The playground is an evaluation image: it keeps all data in memory and is not
# intended for production use.

FROM rust:1.88-slim-bookworm AS builder
WORKDIR /build

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

COPY . .

# A Cargo.lock is required so the image is reproducible from the pinned commit,
# and its absence is the clearest signal that the context is not a core checkout.
RUN test -f Cargo.lock || { \
      echo "Cargo.lock missing from the build context; is it a Streamline core checkout?" >&2; \
      echo "Run scripts/prepare-core-context.sh and build against .build/core." >&2; \
      exit 1; \
    }

RUN cargo build --release --locked --features "full,web-ui"

FROM debian:bookworm-20250224-slim

# Full commit SHA of the core sources in the build context (see core-source.env).
ARG STREAMLINE_CORE_REF=unknown

LABEL org.opencontainers.image.title="Streamline Playground" \
      org.opencontainers.image.description="Streamline playground with demo data and web UI — for evaluation and demos" \
      org.opencontainers.image.source="https://github.com/streamlinelabs/streamline-deploy" \
      org.opencontainers.image.vendor="StreamlineLabs" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="0.2.0" \
      org.opencontainers.image.revision="${STREAMLINE_CORE_REF}" \
      dev.streamline.edition="playground" \
      dev.streamline.features="full,web-ui"

# curl is required by the HEALTHCHECK below; without it the check could only
# ever report unhealthy.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/release/streamline /usr/local/bin/streamline

# Run as a non-root user, matching the official image.
RUN groupadd -r streamline && useradd -r -g streamline -u 1000 streamline

# Create the data directory and hand it to that user *before* switching to it.
# The playground defaults to in-memory storage, but the binary still resolves
# STREAMLINE_DATA_DIR at startup (and `--in-memory` can be turned off with a
# `docker run` argument), so a missing or root-owned /data made the container
# exit on a permission error the moment anything touched disk. Non-root images
# cannot create this directory at run time.
RUN mkdir -p /data && chown -R streamline:streamline /data

EXPOSE 9092 9094
ENV STREAMLINE_IN_MEMORY=true \
    STREAMLINE_PLAYGROUND=true \
    STREAMLINE_LOG_LEVEL=info \
    STREAMLINE_DATA_DIR=/data \
    STREAMLINE_HTTP_ADDR=0.0.0.0:9094 \
    STREAMLINE_LISTEN_ADDR=0.0.0.0:9092
HEALTHCHECK --interval=10s --timeout=3s CMD curl -f http://localhost:9094/health || exit 1

USER 1000:1000

# Explicit start command: the playground flags come from the environment above,
# and the data directory is passed on the command line so the writable path is
# visible in `docker inspect` rather than implied.
ENTRYPOINT ["streamline"]
CMD ["--playground", "--data-dir", "/data"]
