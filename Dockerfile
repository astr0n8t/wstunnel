# Build Stage
ARG BUILDPLATFORM
FROM --platform=${BUILDPLATFORM} rust:latest as rust-source
FROM --platform=${BUILDPLATFORM} ghcr.io/cross-rs/x86_64-unknown-linux-gnu:edge as build_amd64
FROM --platform=${BUILDPLATFORM} ghcr.io/cross-rs/aarch64-unknown-linux-gnu:edge as build_arm64
FROM --platform=${BUILDPLATFORM} ghcr.io/cross-rs/armv7-unknown-linux-gnueabi:edge as build_armv7
FROM --platform=${BUILDPLATFORM} ghcr.io/cross-rs/arm-unknown-linux-gnueabi:edge as build_arm

ARG TARGETARCH
ARG TARGETVARIANT
FROM --platform=${BUILDPLATFORM} build_${TARGETARCH}${TARGETVARIANT} as builder

COPY --from=rust-source /usr/local/rustup /usr/local
COPY --from=rust-source /usr/local/cargo /usr/local

RUN rustup default stable
RUN rustup component add rustfmt clippy

LABEL app="wstunnel"
LABEL REPO="https://github.com/astr0n8t/wstunnel"

ARG TARGETPLATFORM
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then rustup target add x86_64-unknown-linux-gnu; fi

RUN if [ "$TARGETPLATFORM" = "linux/arm64" ]; then rustup target add aarch64-unknown-linux-gnu; fi

RUN if [ "$TARGETPLATFORM" = "linux/arm" ]; then rustup target add arm-unknown-linux-gnueabi; fi

RUN if [ "$TARGETPLATFORM" = "linux/arm/v7" ]; then rustup target add armv7-unknown-linux-gnueabi; fi

WORKDIR /build
COPY . ./


RUN cargo fmt --all -- --check --color=always || (echo "Use cargo fmt to format your code"; exit 1)
RUN cargo clippy --all --all-features -- -D warnings || (echo "Solve your clippy warnings to succeed"; exit 1)

#RUN cargo test --all --all-features
#RUN just test "tcp://localhost:2375" || (echo "Test are failing"; exit 1)

#ENV RUSTFLAGS="-C link-arg=-Wl,--compress-debug-sections=zlib -C force-frame-pointers=yes"
RUN cargo build --tests --all-features
#RUN cargo build --release --all-features


############################################################
# Builder for production image
FROM ${BUILDER_IMAGE} AS builder_release

WORKDIR /build
COPY . ./

ARG BIN_TARGET=--bins
ARG PROFILE=release

#ENV RUSTFLAGS="-C link-arg=-Wl,--compress-debug-sections=zlib -C force-frame-pointers=yes"
RUN cargo build --package=wstunnel-cli --features=jemalloc --profile=${PROFILE} ${BIN_TARGET}

# Translate docker platforms to rust platforms
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then \
        cargo build --release --target x86_64-unknown-linux-gnu --package=wstunnel-cli --features=jemalloc --profile=${PROFILE} ${BIN_TARGET}; \
        cp /build/target/x86_64-unknown-linux-gnu/release/wstunnel /build/wstunnel; \
 fi

RUN if [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
        cargo build --release --target aarch64-unknown-linux-gnu --package=wstunnel-cli --features=jemalloc --profile=${PROFILE} ${BIN_TARGET}; \
        cp /build/target/aarch64-unknown-linux-gnu/release/wstunnel /build/wstunnel; \
 fi

RUN if [ "$TARGETPLATFORM" = "linux/arm/v7" ]; then \
        cargo build --release --target armv7-unknown-linux-gnueabi --package=wstunnel-cli --features=jemalloc --profile=${PROFILE} ${BIN_TARGET}; \
        cp /build/target/armv7-unknown-linux-gnueabi/release/wstunnel /build/wstunnel; \
 fi

RUN if [ "$TARGETPLATFORM" = "linux/arm" ]; then \
        cargo build --release --target arm-unknown-linux-gnueabi --package=wstunnel-cli --features=jemalloc --profile=${PROFILE} ${BIN_TARGET}; \
        cp /build/target/arm-unknown-linux-gnueabi/release/wstunnel /build/wstunnel; \
 fi

# second stage.
FROM gcr.io/distroless/cc-debian12 as build-release-stage

ENV RUST_LOG=info

COPY --from=builder /build/wstunnel /wstunnel

USER nonroot:nonroot

ENV RUST_LOG="INFO"
ENV SERVER_PROTOCOL="wss"
ENV SERVER_LISTEN="[::]"
ENV SERVER_PORT="8080"
EXPOSE 8080

ENTRYPOINT ["/wstunnel"]
CMD ["server", "${SERVER_PROTOCOL}://${SERVER_LISTEN}:${SERVER_PORT}"]

