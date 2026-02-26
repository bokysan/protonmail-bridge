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
    && rm -rf /var/lib/apt/lists/*

FROM go-builder AS supervisord-builder

# Clone and build supervisord (ochinchina version - compatible with Python supervisord config)
RUN git clone https://github.com/ochinchina/supervisord.git /supervisord && \
    cd /supervisord && \
    CGO_ENABLED=0 go build -ldflags="-s -w" -o /supervisord-bin

# Build stage for ProtonMail Bridge
FROM go-builder AS protonmail-builder

# Fetch the latest bridge version from GitHub API and build from source
RUN BRIDGE_VERSION=$(curl -s https://api.github.com/repos/ProtonMail/proton-bridge/releases/latest | jq -r '.tag_name') && \
    cd /tmp && \
    git clone --depth 1 --branch ${BRIDGE_VERSION} https://github.com/ProtonMail/proton-bridge.git && \
    cd proton-bridge && \
    \
    echo "Building ProtonMail Bridge ${BRIDGE_VERSION}" && \
    make build-nogui vault-editor

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
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install architecture-appropriate gosu binary
ARG TARGETARCH=amd64
RUN GOSU_VERSION=1.17 && \
    GOSU_ARCH=${TARGETARCH} && \
    curl -L https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${GOSU_ARCH} -o /usr/local/bin/gosu && \
    chmod +x /usr/local/bin/gosu

# Install architecture-appropriate tini binary
RUN TINI_VERSION=v0.19.0 && \
    TINI_ARCH=${TARGETARCH} && \
    curl -L https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-${TINI_ARCH} -o /sbin/tini && \
    chmod +x /sbin/tini

# Copy supervisord from builder
COPY --from=supervisord-builder /supervisord-bin /usr/local/bin/supervisord
RUN chmod +x /usr/local/bin/supervisord

# Copy ProtonMail Bridge from builder
# Copy protonmail
COPY --from=protonmail-builder /tmp/proton-bridge/bridge /usr/lib/protonmail-bridge/bridge
COPY --from=protonmail-builder /tmp/proton-bridge/proton-bridge /usr/lib/protonmail-bridge/proton-bridge
COPY --from=protonmail-builder /tmp/proton-bridge/vault-editor /usr/lib/protonmail-bridge/vault-editor

RUN chmod +x /usr/lib/protonmail-bridge/bridge && \
    ln -s /usr/lib/protonmail-bridge/bridge /usr/local/bin/protonmail-bridge && \
    chmod +x /usr/lib/protonmail-bridge/proton-bridge && \
    ln -s /usr/lib/protonmail-bridge/proton-bridge /usr/local/bin/proton-bridge && \
    chmod +x /usr/lib/protonmail-bridge/vault-editor && \
    ln -s /usr/lib/protonmail-bridge/vault-editor /usr/local/bin/vault-editor

# Create non-root users
RUN groupadd -r protonmail && \
    useradd -r -g protonmail -d /home/protonmail -s /sbin/nologin protonmail && \
    mkdir -p /home/protonmail && \
    chown -R protonmail:protonmail /home/protonmail && \
    groupadd -r socat && \
    useradd -r -g socat -d /var/lib/socat -s /sbin/nologin socat

# Copy supervisord configuration
COPY supervisord.conf /etc/supervisord.conf

# Copy gpgparams for initialization
COPY gpgparams /protonmail/gpgparams

COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create volume for ProtonMail Bridge configuration
VOLUME ["/home/protonmail"]

# Expose ports: 8025 (SMTP), 8143 (IMAP)
EXPOSE 8025 8143

# Use tini as the entrypoint to handle signals properly
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/entrypoint.sh"]
