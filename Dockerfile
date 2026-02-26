# syntax=docker/dockerfile:1

# Build stage for supervisord
FROM golang:1.26 AS go-builder

ARG TARGETARCH=amd64
ARG TARGETOS=linux

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,id=apt-cache-${TARGETOS}-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,id=apt-lists-${TARGETOS}-${TARGETARCH},sharing=locked \
    apt-get update && apt-get install -y \
    git \
    jq \
    build-essential \
    pkg-config \
    libsecret-1-dev \
    libfido2-dev \
    libcbor-dev \
    && echo "=== Build dependencies installed ==="

FROM go-builder AS supervisord-builder
ARG TARGETARCH
ARG TARGETOS

# Clone and build supervisord (ochinchina version - compatible with Python supervisord config)
RUN --mount=type=cache,target=/root/.cache/go-build,id=go-build-${TARGETOS}-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/go/pkg/mod,id=go-mod-${TARGETOS}-${TARGETARCH},sharing=locked \
    git clone https://github.com/ochinchina/supervisord.git /supervisord && \
    cd /supervisord && \
    echo "=== Building supervisord ===" && \
    CGO_ENABLED=0 go build -ldflags="-s -w" -o /supervisord-bin && \
    echo "=== Build supervisord complete ==="

# Build stage for ProtonMail Bridge
FROM go-builder AS protonmail-builder

ARG TARGETARCH=amd64
ARG TARGETOS=linux

# Fetch the latest bridge version from GitHub API and build from source
WORKDIR /tmp
RUN echo "=== Fetching latest ProtonMail Bridge version ===" && \
    BRIDGE_VERSION=$(curl -s --connect-timeout 5 --max-time 10 --retry 3 --retry-all-errors https://api.github.com/repos/ProtonMail/proton-bridge/releases/latest | jq -r '.tag_name') && \
    printf '%s' "${BRIDGE_VERSION}" > /tmp/bridge_version.txt && \
    echo "=== Latest ProtonMail Bridge version: ${BRIDGE_VERSION} ==="
RUN git clone --depth 1 --branch $(cat /tmp/bridge_version.txt) https://github.com/ProtonMail/proton-bridge.git
WORKDIR /tmp/proton-bridge
RUN --mount=type=cache,target=/root/.cache/go-build,id=go-build-${TARGETOS}-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/go/pkg/mod,id=go-mod-${TARGETOS}-${TARGETARCH},sharing=locked \
    echo "=== Downloading dependencies ===" && \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} go mod download -x && \
    echo "=== Dependencies downloaded ==="
RUN --mount=type=cache,target=/root/.cache/go-build,id=go-build-${TARGETOS}-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/go/pkg/mod,id=go-mod-${TARGETOS}-${TARGETARCH},sharing=locked \
    echo "=== Building ProtonMail Bridge ===" && \
    set -x && \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} BUILD_FLAGS="-v" make build-nogui vault-editor 2>&1 | tee /tmp/build.log && \
    echo "=== Build ProtonMail Bridge complete ===" && \
    du -sh /tmp/proton-bridge && \
    echo "Build completed successfully"

# Final image
FROM debian:bookworm-slim

ARG TARGETARCH=amd64
ARG TARGETOS=linux

ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies
RUN --mount=type=cache,target=/var/cache/apt,id=apt-cache-${TARGETOS}-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,id=apt-lists-${TARGETOS}-${TARGETARCH},sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    socat \
    curl \
    jq \
    wget \
    pass \
    libsecret-1-0 \
    libfido2-1 \
    libcbor0.8 \
    ca-certificates \
    && echo "=== Runtime dependencies installed ==="

# Install architecture-appropriate gosu binary
RUN GOSU_VERSION=1.17 && \
    GOSU_ARCH=${TARGETARCH} && \
    curl -L --connect-timeout 5 --max-time 10 --retry 3 --retry-all-errors https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${GOSU_ARCH} -o /usr/local/bin/gosu && \
    chmod +x /usr/local/bin/gosu && \
    echo "=== gosu installed ==="

# Install architecture-appropriate tini binary
RUN TINI_VERSION=v0.19.0 && \
    TINI_ARCH=${TARGETARCH} && \
    curl -L --connect-timeout 5 --max-time 10 --retry 3 --retry-all-errors https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-${TINI_ARCH} -o /sbin/tini && \
    chmod +x /sbin/tini && \
    echo "=== tini installed ==="

# Copy supervisord from builder
COPY --from=supervisord-builder /supervisord-bin /usr/local/bin/supervisord
COPY --from=protonmail-builder /tmp/proton-bridge/bridge /usr/lib/protonmail-bridge/bridge
COPY --from=protonmail-builder /tmp/proton-bridge/proton-bridge /usr/lib/protonmail-bridge/proton-bridge
COPY --from=protonmail-builder /tmp/proton-bridge/vault-editor /usr/lib/protonmail-bridge/vault-editor

RUN echo "=== Copying supervisord and ProtonMail Bridge binaries ===" && \
    chmod +x /usr/local/bin/supervisord && \
    chmod +x /usr/lib/protonmail-bridge/bridge && \
    ln -s /usr/lib/protonmail-bridge/bridge /usr/local/bin/protonmail-bridge && \
    chmod +x /usr/lib/protonmail-bridge/proton-bridge && \
    ln -s /usr/lib/protonmail-bridge/proton-bridge /usr/local/bin/proton-bridge && \
    chmod +x /usr/lib/protonmail-bridge/vault-editor && \
    ln -s /usr/lib/protonmail-bridge/vault-editor /usr/local/bin/vault-editor && \
    groupadd -r protonmail && \
    useradd -r -g protonmail -d /home/protonmail -s /sbin/nologin protonmail && \
    mkdir -p /home/protonmail && \
    chown -R protonmail:protonmail /home/protonmail && \
    groupadd -r socat && \
    useradd -r -g socat -d /var/lib/socat -s /sbin/nologin socat && \
    echo "=== ProtonMail Bridge and supervisord installed ==="

# Copy supervisord configuration
COPY supervisord.conf /etc/supervisord.conf

# Copy gpgparams for initialization
COPY gpgparams /protonmail/gpgparams

COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && \
    echo "=== Entry point script installed ==="

# Create volume for ProtonMail Bridge configuration
VOLUME ["/home/protonmail"]

# Expose ports: 8025 (SMTP), 8143 (IMAP)
EXPOSE 8025 8143

# Use tini as the entrypoint to handle signals properly
ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
CMD []
