# =============================================================================
# Official Streamline image
# =============================================================================
# IMPORTANT: the build context for this Dockerfile is the *Streamline core*
# source tree, not this repository. streamline-deploy ships deployment
# artifacts only and contains no Rust sources.
#
# Prepare the context from the commit pinned in core-source.env:
#
#   scripts/prepare-core-context.sh            # -> .build/core
#   docker build -f Dockerfile .build/core \
#     --build-arg STREAMLINE_EDITION=full \
#     --build-arg STREAMLINE_FEATURES=full \
#     --build-arg STREAMLINE_CORE_REF=<pinned sha> \
#     -t streamline:dev
#
# or simply `make docker`.
#
# Editions
#   standard — default cargo features (STREAMLINE_FEATURES must be empty). TLS
#              is compiled into every build, but the image does NOT advertise
#              SASL auth or clustering support; the Helm chart refuses to
#              enable them.
#   full     — STREAMLINE_FEATURES must be exactly "full": core's own
#              meta-feature, which is what makes "full" a knowable capability
#              set (SASL auth + clustering). An arbitrary list passed as
#              "full" used to mint an image that claimed capabilities cargo had
#              never compiled, so anything else is rejected here.
#   custom   — any other feature list. Because the list is arbitrary, nothing
#              about the resulting image is inferable, so a custom build MUST
#              declare what it supports with STREAMLINE_CAPABILITIES (a comma
#              list of auth, clustering, moonshot — or the literal "none").
#              That declaration is recorded in the
#              dev.streamline.capabilities label and is what the Helm chart's
#              image.capabilities must mirror; the chart never guesses.
#
#   scripts/prepare-core-context.sh            # -> .build/core
#   docker build -f Dockerfile .build/core \
#     --build-arg STREAMLINE_EDITION=custom \
#     --build-arg STREAMLINE_FEATURES=cdc,analytics \
#     --build-arg STREAMLINE_CAPABILITIES=none \
#     --build-arg STREAMLINE_CORE_REF=<pinned sha> \
#     -t streamline-cdc:dev
#
# The edition, feature list and declared capabilities are recorded as image
# labels so deployments can be checked against the capabilities they require.
# =============================================================================

# Build stage
FROM rust:1.88-slim-bookworm AS builder

ARG STREAMLINE_EDITION=standard
ARG STREAMLINE_FEATURES=""
ARG STREAMLINE_CAPABILITIES=""

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    g++ \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Fail closed on an edition/feature mismatch instead of shipping an image that
# silently lacks the advertised capabilities. "full" is a capability claim, so
# it is tied to the one feature list that is known to back it (core's "full"
# meta-feature); every other list is a custom build that has to say what it
# supports.
RUN set -eu; \
    case "$STREAMLINE_EDITION" in \
      standard) \
        if [ -n "$STREAMLINE_FEATURES" ]; then \
          echo "STREAMLINE_EDITION=standard must not set STREAMLINE_FEATURES ($STREAMLINE_FEATURES). Use STREAMLINE_EDITION=custom for an explicit feature list." >&2; \
          exit 1; \
        fi; \
        if [ -n "$STREAMLINE_CAPABILITIES" ]; then \
          echo "STREAMLINE_EDITION=standard must not set STREAMLINE_CAPABILITIES ($STREAMLINE_CAPABILITIES): the standard edition advertises no optional capabilities." >&2; \
          exit 1; \
        fi ;; \
      full) \
        if [ "$STREAMLINE_FEATURES" != "full" ]; then \
          echo "STREAMLINE_EDITION=full accepts only STREAMLINE_FEATURES=full (got '${STREAMLINE_FEATURES}'). 'full' is core's own meta-feature and is what makes this edition's capability set (SASL auth, clustering) knowable; build any other list with STREAMLINE_EDITION=custom and declare STREAMLINE_CAPABILITIES." >&2; \
          exit 1; \
        fi; \
        if [ -n "$STREAMLINE_CAPABILITIES" ]; then \
          echo "STREAMLINE_EDITION=full must not set STREAMLINE_CAPABILITIES ($STREAMLINE_CAPABILITIES): the full edition's capabilities are implied by STREAMLINE_FEATURES=full (auth, clustering)." >&2; \
          exit 1; \
        fi ;; \
      custom) \
        if [ -z "$STREAMLINE_FEATURES" ]; then \
          echo "STREAMLINE_EDITION=custom requires STREAMLINE_FEATURES (e.g. --build-arg STREAMLINE_FEATURES=cdc,analytics). Use STREAMLINE_EDITION=standard for the default feature set." >&2; \
          exit 1; \
        fi; \
        if [ "$STREAMLINE_FEATURES" = "full" ]; then \
          echo "STREAMLINE_FEATURES=full is the full edition; build it with STREAMLINE_EDITION=full so its capabilities are recorded consistently." >&2; \
          exit 1; \
        fi; \
        if [ -z "$STREAMLINE_CAPABILITIES" ]; then \
          echo "STREAMLINE_EDITION=custom requires STREAMLINE_CAPABILITIES: a comma-separated list of auth, clustering, moonshot — or the literal 'none'. An arbitrary feature list tells a deployment nothing, and the Helm chart refuses to guess (image.capabilities must mirror this declaration)." >&2; \
          exit 1; \
        fi; \
        old_ifs="$IFS"; IFS=','; \
        set -- $STREAMLINE_CAPABILITIES; \
        IFS="$old_ifs"; \
        for cap in "$@"; do \
          case "$cap" in \
            auth|clustering|moonshot|none) ;; \
            *) echo "Unsupported capability '$cap' in STREAMLINE_CAPABILITIES (expected: auth, clustering, moonshot, none)" >&2; exit 1 ;; \
          esac; \
        done ;; \
      *) \
        echo "Unsupported STREAMLINE_EDITION='$STREAMLINE_EDITION' (expected: standard, full, custom)" >&2; \
        exit 1 ;; \
    esac

# Copy the prepared core source tree. Copying the whole context keeps this
# Dockerfile valid for any core workspace layout; per-crate COPY lists silently
# break whenever core adds or renames a crate.
COPY . .

# A Cargo.lock is required so the image is reproducible from the pinned commit.
RUN test -f Cargo.lock || { \
      echo "Cargo.lock missing from the build context; is it a Streamline core checkout?" >&2; \
      exit 1; \
    }

RUN set -eu; \
    if [ -n "$STREAMLINE_FEATURES" ]; then \
      cargo build --release --locked --features "$STREAMLINE_FEATURES"; \
    else \
      cargo build --release --locked; \
    fi

# Runtime stage
FROM debian:bookworm-20250224-slim

ARG STREAMLINE_EDITION=standard
ARG STREAMLINE_FEATURES=""
ARG STREAMLINE_CAPABILITIES=""
# Version of the deployment artifacts / release this image belongs to.
ARG STREAMLINE_VERSION=0.4.0
# Full commit SHA of the core sources in the build context (see core-source.env).
ARG STREAMLINE_CORE_REF=unknown

LABEL org.opencontainers.image.title="Streamline" \
      org.opencontainers.image.description="The Redis of Streaming — Kafka-compatible, single-binary streaming platform" \
      org.opencontainers.image.url="https://github.com/streamlinelabs/streamline" \
      org.opencontainers.image.source="https://github.com/streamlinelabs/streamline-deploy" \
      org.opencontainers.image.vendor="StreamlineLabs" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${STREAMLINE_VERSION}" \
      org.opencontainers.image.revision="${STREAMLINE_CORE_REF}" \
      dev.streamline.edition="${STREAMLINE_EDITION}" \
      dev.streamline.features="${STREAMLINE_FEATURES}" \
      dev.streamline.capabilities="${STREAMLINE_CAPABILITIES}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy binaries from builder
COPY --from=builder /app/target/release/streamline /usr/local/bin/
COPY --from=builder /app/target/release/streamline-cli /usr/local/bin/

# Create non-root user
RUN groupadd -r streamline && useradd -r -g streamline -u 1000 streamline

# Create data directory
RUN mkdir -p /data && chown -R streamline:streamline /data

# Set environment variables
ENV STREAMLINE_DATA_DIR=/data
ENV STREAMLINE_LISTEN_ADDR=0.0.0.0:9092
ENV STREAMLINE_LOG_LEVEL=info
ENV RUST_LOG=info

# Expose ports
EXPOSE 9092
EXPOSE 9094

# Create volume for data persistence
VOLUME ["/data"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:9094/health/live || exit 1

# Switch to non-root user
USER 1000:1000

# Run the server
ENTRYPOINT ["streamline"]
CMD ["--listen-addr", "0.0.0.0:9092", "--data-dir", "/data"]
