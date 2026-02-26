# Build stage for supervisord
FROM golang:1.26 AS supervisord-builder

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# Clone and build supervisord (ochinchina version - compatible with Python supervisord config)
RUN git clone https://github.com/ochinchina/supervisord.git /supervisord && \
    cd /supervisord && \
    go build -ldflags="-s -w" -o /supervisord-bin

# Main image
FROM fedora:latest

# Install dependencies
RUN dnf install -y \
    socat \
    curl \
    jq \
    wget \
    && dnf clean all

# Install tini
RUN curl -L https://github.com/krallin/tini/releases/download/v0.19.0/tini -o /sbin/tini && \
    chmod +x /sbin/tini

# Copy supervisord from builder stage
COPY --from=supervisord-builder /supervisord-bin /usr/local/bin/supervisord
RUN chmod +x /usr/local/bin/supervisord

# Fetch the latest bridge version from GitHub API and install
RUN BRIDGE_VERSION=$(curl -s https://api.github.com/repos/ProtonMail/proton-bridge/releases/latest | jq -r '.tag_name' | sed 's/^v//') \
    && echo "Installing ProtonMail Bridge version ${BRIDGE_VERSION}" \
    && wget https://github.com/ProtonMail/proton-bridge/releases/download/v${BRIDGE_VERSION}/protonmail-bridge-${BRIDGE_VERSION}-1.x86_64.rpm \
    && dnf install -y ./protonmail-bridge-${BRIDGE_VERSION}-1.x86_64.rpm \
    && rm ./protonmail-bridge-${BRIDGE_VERSION}-1.x86_64.rpm

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
ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
CMD []
