# Build stage
FROM rust:1.93-slim-bookworm AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Copy manifests (root + workspace crates)
COPY Cargo.toml Cargo.lock* ./
COPY crates/streamline-analytics/Cargo.toml crates/streamline-analytics/Cargo.toml
COPY crates/streamline-wasm/Cargo.toml crates/streamline-wasm/Cargo.toml
COPY streamline-operator/Cargo.toml streamline-operator/Cargo.toml

# Create dummy source files to cache dependencies
RUN mkdir -p src crates/streamline-analytics/src crates/streamline-wasm/src streamline-operator/src && \
    echo "fn main() {}" > src/main.rs && \
    echo "fn main() {}" > src/cli.rs && \
    echo "" > src/lib.rs && \
    echo "" > crates/streamline-analytics/src/lib.rs && \
    echo "" > crates/streamline-wasm/src/lib.rs && \
    echo "fn main() {}" > streamline-operator/src/main.rs

# Build dependencies only (for caching)
RUN cargo build --release 2>/dev/null || true && \
    rm -rf src crates/streamline-analytics/src crates/streamline-wasm/src streamline-operator/src

# Copy actual source code
COPY src ./src
COPY crates ./crates
COPY streamline-operator ./streamline-operator

# Touch files to ensure rebuild
RUN touch src/main.rs src/cli.rs src/lib.rs

# Build the actual binaries
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-20260223-slim

RUN apt-get update && apt-get install -y \
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
