#!/bin/sh
# Streamline Installer — https://streamline.dev
#
# Usage:
#   curl -fsSL https://get.streamline.dev | sh
#   curl -fsSL https://get.streamline.dev | sh -s -- --version 0.2.0
#   curl -fsSL https://get.streamline.dev | sh -s -- --prefix /usr/local
#
# Installs the `streamline` server and `streamline-cli` binaries.

set -eu

REPO="streamlinelabs/streamline"
DEFAULT_VERSION="latest"
PREFIX="${PREFIX:-/usr/local/bin}"
VERSION=""

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --prefix)  PREFIX="$2"; shift 2 ;;
        --help)
            echo "Usage: curl -fsSL https://get.streamline.dev | sh"
            echo ""
            echo "Options:"
            echo "  --version VERSION  Install a specific version (e.g., 0.2.0)"
            echo "  --prefix PATH      Install to PATH (default: /usr/local/bin)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Detect OS and architecture
detect_platform() {
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m)"

    case "$OS" in
        linux)  OS="linux" ;;
        darwin) OS="darwin" ;;
        mingw*|msys*|cygwin*) OS="windows" ;;
        *) echo "Unsupported OS: $OS"; exit 1 ;;
    esac

    case "$ARCH" in
        x86_64|amd64)  ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        armv7l)        ARCH="armv7" ;;
        *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac

    PLATFORM="${OS}-${ARCH}"
}

# Get the latest release version from GitHub
get_latest_version() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/'
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/'
    else
        echo "Error: curl or wget required" >&2
        exit 1
    fi
}

# Download and install binary
install_binary() {
    local name="$1"
    local url="https://github.com/${REPO}/releases/download/v${VERSION}/${name}-${PLATFORM}"

    if [ "$OS" = "windows" ]; then
        url="${url}.exe"
    fi

    echo "  Downloading ${name}..."
    local tmpfile
    tmpfile="$(mktemp)"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$tmpfile" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$tmpfile" 2>/dev/null
    fi

    if [ ! -s "$tmpfile" ]; then
        echo "  ⚠ Failed to download ${name} (may not be available for ${PLATFORM})"
        rm -f "$tmpfile"
        return 1
    fi

    chmod +x "$tmpfile"

    if [ -w "$PREFIX" ]; then
        mv "$tmpfile" "${PREFIX}/${name}"
    else
        echo "  Installing to ${PREFIX} (requires sudo)..."
        sudo mv "$tmpfile" "${PREFIX}/${name}"
    fi

    echo "  ✓ Installed ${name} to ${PREFIX}/${name}"
}

main() {
    echo ""
    echo "  ⚡ Streamline Installer"
    echo "  ─────────────────────────"
    echo ""

    detect_platform
    echo "  Platform: ${PLATFORM}"

    if [ -z "$VERSION" ] || [ "$VERSION" = "latest" ]; then
        echo "  Fetching latest version..."
        VERSION="$(get_latest_version)"
        if [ -z "$VERSION" ]; then
            VERSION="0.2.0"
            echo "  ⚠ Could not detect latest version, using ${VERSION}"
        fi
    fi
    echo "  Version:  ${VERSION}"
    echo "  Prefix:   ${PREFIX}"
    echo ""

    # Ensure prefix directory exists
    mkdir -p "$PREFIX" 2>/dev/null || sudo mkdir -p "$PREFIX"

    install_binary "streamline"
    install_binary "streamline-cli"

    echo ""
    echo "  ✅ Installation complete!"
    echo ""
    echo "  Quick start:"
    echo "    streamline                    # Start server"
    echo "    streamline-cli topics list    # List topics"
    echo ""
    echo "  Documentation: https://streamlinelabs.dev"
    echo ""
}

main "$@"
