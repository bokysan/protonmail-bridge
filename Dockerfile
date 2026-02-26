# Build stage for supervisord
FROM golang:1.26 AS go-builder

RUN apt-get update && apt-get install -y \
    git \
    jq \
    build-essential \
    pkg-config \
    libsecret-1-dev \
    libfido2-dev \
    libcbor-dev \
    && rm -rf /var/lib/apt/lists/* && \
    echo "=== Build dependencies installed ==="

FROM go-builder AS supervisord-builder

# Clone and build supervisord (ochinchina version - compatible with Python supervisord config)
RUN git clone https://github.com/ochinchina/supervisord.git /supervisord && \
    cd /supervisord && \
    echo "=== Building supervisord ===" && \
    CGO_ENABLED=0 go build -ldflags="-s -w" -o /supervisord-bin && \
    echo "=== Build supervisord complete ==="

# Build stage for ProtonMail Bridge
FROM go-builder AS protonmail-builder

# Fetch the latest bridge version from GitHub API and build from source
WORKDIR /tmp
RUN echo "=== Fetching latest ProtonMail Bridge version ===" && \
    BRIDGE_VERSION=$(curl -s --connect-timeout 5 --max-time 10 --retry 3 --retry-all-errors https://api.github.com/repos/ProtonMail/proton-bridge/releases/latest | jq -r '.tag_name') && \
    printf '%s' "${BRIDGE_VERSION}" > /tmp/bridge_version.txt && \
    echo "=== Latest ProtonMail Bridge version: ${BRIDGE_VERSION} ==="
RUN git clone --depth 1 --branch $(cat /tmp/bridge_version.txt) https://github.com/ProtonMail/proton-bridge.git
WORKDIR /tmp/proton-bridge
RUN echo "=== Building ProtonMail Bridge ===" && \
    BUILD_FLAGS="-v" make -d build-nogui vault-editor && \
    echo "=== Build ProtonMail Bridge complete ==="

# Final image
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    socat \
    curl \
    jq \
    wget \
    pass \
    libsecret-1-0 \
    libfido2-1 \
    libcbor0.8 \
    ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo "=== Runtime dependencies installed ==="

# Install architecture-appropriate gosu binary
ARG TARGETARCH=amd64
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
RUN 

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
