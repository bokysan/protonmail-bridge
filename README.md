# ProtonMail Bridge Docker Image

A lightweight, production-ready Docker image for [ProtonMail Bridge](https://github.com/ProtonMail/proton-bridge) with proper process management and security.

## Features

- **Minimal base image**: Uses `fedora:latest` with minimal dependencies
- **Automatic version detection**: Fetches the latest ProtonMail Bridge version from GitHub API during build
- **Automatic version tracking**: Weekly checks for new ProtonMail Bridge releases and auto-tags this repository
- **Non-root execution**: Both ProtonMail Bridge and socat run as unprivileged users
- **Process supervision**: Uses [supervisord (Go)](https://github.com/ochinchina/supervisord) built from source for process management with automatic restart on failure
- **Proper signal handling**: Uses [tini](https://github.com/krallin/tini) as PID 1 for correct signal propagation
- **Clean logging**: All logs directed to stdout for easy container log viewing
- **No privileged ports**: socat runs on high-numbered ports (8025 for SMTP, 8143 for IMAP)
- **AMD64 only**: Built specifically for x86_64 architecture to match ProtonMail Bridge releases

## Ports

The image exposes the following ports:

- **8025**: SMTP (forwarded to ProtonMail Bridge SMTP port 1025)
- **8143**: IMAP (forwarded to ProtonMail Bridge IMAP port 1143)

The internal socat proxies ensure that connections appear to come from `127.0.0.1`, which is required by ProtonMail Bridge.

## Usage

### Basic Usage

Run the container in daemon mode:

```bash
docker run -d \
  --name protonmail-bridge \
  -p 8025:8025 \
  -p 8143:8143 \
  -v protonmail_config:/home/protonmail \
  your-image-name
```

### Initialization

Before running the bridge in daemon mode, you typically need to authenticate. Run the init command:

```bash
docker run --rm \
  -v protonmail_config:/home/protonmail \
  your-image-name init
```

This will:
- Generate a GPG key for credential storage
- Initialize the `pass` password manager
- Prompt you to log in with your ProtonMail credentials

### Passing Arguments to ProtonMail Bridge

You can pass any ProtonMail Bridge CLI arguments directly:

```bash
# Get version
docker run --rm your-image-name version

# Get help
docker run --rm your-image-name help

# Check status
docker run --rm your-image-name status
```

The image automatically passes any arguments to `/opt/protonmail/proton-bridge --cli <args>`.

## Volume Mounts

The image defines a volume at `/home/protonmail` where ProtonMail Bridge stores:
- Configuration files
- Cached credentials
- GPG keys and password store

**Important**: Persist this volume between container restarts to maintain your login session:

```bash
docker run -d \
  -v protonmail_config:/home/protonmail \
  your-image-name
```

## Configuration

### Custom Supervisord Configuration

If you need to customize the supervisord configuration (e.g., adjust logging, add additional programs), you can mount a custom `supervisord.conf`:

```bash
docker run -d \
  -v ./custom-supervisord.conf:/etc/supervisord.conf \
  -v protonmail_config:/home/protonmail \
  -p 8025:8025 \
  -p 8143:8143 \
  your-image-name
```

### Environment Variables

You can set custom environment variables if needed:

```bash
docker run -d \
  -e HOME=/home/protonmail \
  -v protonmail_config:/home/protonmail \
  -p 8025:8025 \
  -p 8143:8143 \
  your-image-name
```

## Docker Compose Example

```yaml
version: '3.8'

services:
  protonmail-bridge:
    build: .
    container_name: protonmail-bridge
    ports:
      - "8025:8025"  # SMTP
      - "8143:8143"  # IMAP
    volumes:
      - protonmail_config:/home/protonmail
    restart: unless-stopped
    # Optional: uncomment for initialization
    # command: init

volumes:
  protonmail_config:
```

## Building the Image

### Local Build

```bash
docker build -t protonmail-bridge .
```

The build uses a multi-stage process:
1. **Builder stage**: Compiles supervisord from source using Go
2. **Main stage**: 
   - Downloads the latest ProtonMail Bridge version from GitHub
   - Copies the compiled supervisord binary
   - Installs tini for proper signal handling
   - Sets up non-root users (protonmail and socat)

### CI/CD with GitHub Actions

This repository includes automated Docker image builds and version tracking using GitHub Actions:

#### Automatic Version Tracking

- **Weekly checks**: Every Monday, the workflow checks for new ProtonMail Bridge releases
- **Automatic tagging**: When a new ProtonMail Bridge version is released (e.g., `v3.23.0`), the repository automatically creates a matching tag
- **Automatic builds**: The new tag triggers a Docker build with the latest ProtonMail Bridge version

#### Build Triggers

- **Edge builds**: Automatically built from the `main` branch and tagged as `:edge`
- **Version builds**: Triggered by version tags (e.g., `v3.22.0`) and tagged as:
  - `:3.22.0` (full version)
  - `:3.22` (major.minor)
  - `:latest` (latest release)

#### Platform Support

All Docker images are built for `linux/amd64` only, as ProtonMail Bridge does not provide ARM64 builds. This ensures compatibility when building on macOS with Apple Silicon using Docker's emulation.

#### Manual Release

You can also manually trigger a release:
```bash
git tag v3.22.0
git push origin v3.22.0
```

#### Using Pre-built Images

Pre-built images are available from GitHub Container Registry:
```bash
# Latest stable version
docker pull ghcr.io/<owner>/<repo>:latest

# Specific version
docker pull ghcr.io/<owner>/<repo>:3.22.0

# Latest edge build from main
docker pull ghcr.io/<owner>/<repo>:edge
```

## Process Management

The container runs three supervised processes:

1. **protonmail-bridge**: The main ProtonMail Bridge service (runs as `protonmail` user)
2. **socat-smtp**: SMTP proxy (port 8025 → 1025) (runs as `socat` user)
3. **socat-imap**: IMAP proxy (port 8143 → 1143) (runs as `socat` user)

Supervisord automatically restarts any failed processes.

## Logs

All logs are directed to stdout and can be viewed with:

```bash
docker logs -f protonmail-bridge
```

## Security Considerations

- **Non-root processes**: ProtonMail Bridge and socat run as unprivileged users
- **No privileged ports**: The image uses high-numbered ports (8025, 8143) instead of privileged ports (25, 143)
- **Volume isolation**: Configuration is isolated in a volume, not in the container layer
- **Minimal base**: Uses `fedora:latest` with minimal dependencies

## Troubleshooting

### Container exits immediately
Check the logs:
```bash
docker logs protonmail-bridge
```

### Bridge not authenticating
Ensure you've run the init command first and persisted the volume:
```bash
docker run --rm \
  -v protonmail_config:/home/protonmail \
  your-image-name init
```

### Connection refused on ports 8025/8143
- Ensure ports are mapped: `-p 8025:8025 -p 8143:8143`
- Check that supervisord is running: `docker exec protonmail-bridge supervisorctl status`

### Permission denied errors
The container uses non-root users. Ensure volume permissions allow read/write by the container users (uid 1000+).

## References

- [ProtonMail Bridge Documentation](https://proton.me/support/proton-mail-bridge-cli)
- [ProtonMail Bridge Releases](https://github.com/ProtonMail/proton-bridge/releases)
- [Supervisord Documentation](https://github.com/ochinchina/supervisord)
- [Tini Documentation](https://github.com/krallin/tini)
