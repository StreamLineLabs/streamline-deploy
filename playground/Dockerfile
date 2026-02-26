FROM rust:1.80-slim-bookworm AS builder
WORKDIR /build
COPY . .
RUN cargo build --release --features "full,web-ui"

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/target/release/streamline /usr/local/bin/streamline
EXPOSE 9092 9094
ENV STREAMLINE_IN_MEMORY=true \
    STREAMLINE_PLAYGROUND=true \
    STREAMLINE_LOG_LEVEL=info \
    STREAMLINE_HTTP_ADDR=0.0.0.0:9094 \
    STREAMLINE_LISTEN_ADDR=0.0.0.0:9092
HEALTHCHECK --interval=10s --timeout=3s CMD curl -f http://localhost:9094/health || exit 1
ENTRYPOINT ["streamline"]
