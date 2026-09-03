#!/bin/sh
# Streamline prebuilt installer (currently unavailable)
#
# No controlled installer endpoint or verified release archive set exists yet.
# Build the server and CLI from source instead:
#
#   git clone https://github.com/streamlinelabs/streamline.git
#   cd streamline
#   cargo build --release
#
# The release-resolution and integrity helpers below are retained for future
# controlled assets, but the executable entry point fails before network or
# filesystem mutation. When enabled later, archives must still pass mandatory
# checksum verification; there is no bypass flag.

set -eu

INSTALLER_RELEASES_AVAILABLE=0
readonly INSTALLER_RELEASES_AVAILABLE
REPO="${STREAMLINE_REPO:-streamlinelabs/streamline}"
PREFIX="${PREFIX:-/usr/local/bin}"
VERSION=""
ASSET_OVERRIDE=""
# Which C library flavour to prefer when a Linux release publishes both. glibc
# is the default because it matches the mainstream distributions; musl builds
# are selected explicitly with --libc musl (or STREAMLINE_LIBC=musl). The
# request is a filter, not a preference: if the release publishes flavoured
# archives but none of the requested flavour, the installer stops rather than
# install the other one.
LIBC="${STREAMLINE_LIBC:-gnu}"

OS=""
ARCH=""
PLATFORM=""
ARCH_ALTERNATIVES=""

die() {
    echo "  ✗ $*" >&2
    exit 1
}

usage() {
    echo "Streamline prebuilt installation is currently unavailable."
    echo "No controlled installer endpoint or verified release archive set exists yet."
    echo ""
    echo "Build from source:"
    echo "  git clone https://github.com/streamlinelabs/streamline.git"
    echo "  cd streamline"
    echo "  cargo build --release"
}

# --- HTTP -------------------------------------------------------------------

http_get() {
    # http_get <url>  — writes the body to stdout
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$1"
    else
        die "curl or wget is required"
    fi
}

http_download() {
    # http_download <url> <dest>
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$1" -O "$2"
    else
        die "curl or wget is required"
    fi
}

# --- Platform ---------------------------------------------------------------

detect_platform_from() {
    # detect_platform_from <uname -s> <uname -m>
    _os="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    _arch="$2"

    case "$_os" in
        linux)  OS="linux" ;;
        darwin) OS="darwin" ;;
        mingw*|msys*|cygwin*|windows*) OS="windows" ;;
        *) die "Unsupported OS: $_os" ;;
    esac

    case "$_arch" in
        x86_64|amd64)  ARCH="x86_64";  ARCH_ALTERNATIVES="x86_64 amd64" ;;
        aarch64|arm64) ARCH="aarch64"; ARCH_ALTERNATIVES="aarch64 arm64" ;;
        armv7l|armv7)  ARCH="armv7";   ARCH_ALTERNATIVES="armv7 armv7l armhf" ;;
        *) die "Unsupported architecture: $_arch" ;;
    esac

    PLATFORM="${OS}-${ARCH}"
}

detect_platform() {
    detect_platform_from "$(uname -s)" "$(uname -m)"
}

# --- Release metadata -------------------------------------------------------

release_json() {
    # release_json <tag|latest>
    if [ "$1" = "latest" ]; then
        http_get "https://api.github.com/repos/${REPO}/releases/latest"
    else
        http_get "https://api.github.com/repos/${REPO}/releases/tags/$1"
    fi
}

parse_tag_name() {
    # Reads release JSON on stdin, writes the version without a leading "v".
    grep '"tag_name"' | head -n 1 | sed -E 's/.*"tag_name"[^"]*"v?([^"]+)".*/\1/'
}

parse_asset_names() {
    # Reads release JSON on stdin, writes one asset name per line.
    tr ',' '\n' | grep '"name"' | sed -E 's/.*"name"[^"]*"([^"]+)".*/\1/'
}

# --- Asset resolution -------------------------------------------------------

is_metadata_asset() {
    case "$1" in
        *.sha256|*.sha256sum|*SHA256SUMS*|*sha256sums*|*checksums*|*CHECKSUMS*|*.sig|*.asc|*.pem|*.sbom|*.json) return 0 ;;
        *) return 1 ;;
    esac
}

select_asset() {
    # select_asset <os> <arch alternatives> [libc preference]
    #   asset names on stdin
    _sel_os="$1"
    _sel_arches="$2"
    _sel_libc="${3:-$LIBC}"
    _matches=""
    _count=0

    while IFS= read -r _name; do
        [ -n "$_name" ] || continue
        if is_metadata_asset "$_name"; then continue; fi
        case "$_name" in
            *.tar.gz|*.tgz|*.zip) ;;
            *) continue ;;
        esac
        case "$_name" in
            *"$_sel_os"*) ;;
            *) continue ;;
        esac
        for _alt in $_sel_arches; do
            case "$_name" in
                *"$_alt"*)
                    _matches="${_matches}${_name}
"
                    _count=$((_count + 1))
                    break
                    ;;
            esac
        done
    done

    if [ "$_count" -eq 0 ]; then
        echo "no release archive found for ${_sel_os} (${_sel_arches})" >&2
        return 1
    fi

    # Linux releases commonly publish both a glibc and a musl archive for the
    # same architecture. Filter to the REQUESTED flavour *before* deciding
    # whether the remaining match is unique. Resolving uniqueness first meant a
    # release that shipped only a musl build satisfied `--libc gnu` — one
    # candidate, therefore "unambiguous" — and installed binaries that will not
    # start on a glibc host. Asking for a flavour that is not published is an
    # error, never a silent substitution.
    if [ "$_sel_os" = "linux" ]; then
        _libc_matches=""
        _libc_count=0
        _flavoured=0
        while IFS= read -r _name; do
            [ -n "$_name" ] || continue
            # Only apply the filter when the release actually distinguishes
            # flavours; a single unqualified `...-linux-x86_64.tar.gz` carries
            # no libc information to filter on.
            case "$_name" in
                *gnu*|*musl*) _flavoured=$((_flavoured + 1)) ;;
            esac
            case "$_name" in
                *"$_sel_libc"*)
                    _libc_matches="${_libc_matches}${_name}
"
                    _libc_count=$((_libc_count + 1))
                    ;;
            esac
        done <<EOF
$_matches
EOF
        if [ "$_flavoured" -gt 0 ]; then
            if [ "$_libc_count" -eq 0 ]; then
                echo "release publishes no ${_sel_libc} archive for ${_sel_os} (${_sel_arches}); it publishes:" >&2
                printf '%s' "$_matches" >&2
                echo "refusing to install a different C library flavour than requested — binaries built against the other libc may not run here." >&2
                echo "re-run with --libc gnu|musl to pick a published flavour deliberately, or --asset NAME to name an archive." >&2
                return 1
            fi
            _matches="$_libc_matches"
            _count=$_libc_count
        fi
    fi

    if [ "$_count" -gt 1 ]; then
        echo "multiple release archives match ${_sel_os} (${_sel_arches}):" >&2
        printf '%s' "$_matches" >&2
        echo "re-run with --asset NAME (or --libc gnu|musl on Linux) to choose one" >&2
        return 1
    fi
    printf '%s' "$_matches" | head -n 1
}

select_checksum_asset() {
    # select_checksum_asset <archive name>  — asset names on stdin
    _archive="$1"
    _names="$(cat)"

    for _candidate in "${_archive}.sha256" "${_archive}.sha256sum"; do
        if printf '%s\n' "$_names" | grep -Fxq "$_candidate"; then
            printf '%s' "$_candidate"
            return 0
        fi
    done

    _sums="$(printf '%s\n' "$_names" \
        | grep -E '^(SHA256SUMS|sha256sums|checksums|CHECKSUMS)(\.txt)?$' \
        | head -n 1)"
    if [ -n "$_sums" ]; then
        printf '%s' "$_sums"
        return 0
    fi

    echo "release ${VERSION:-?} publishes no checksum file for ${_archive}; refusing to install unverified binaries" >&2
    return 1
}

# --- Integrity --------------------------------------------------------------

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        die "sha256sum or shasum is required to verify downloads"
    fi
}

checksum_for_asset() {
    # checksum_for_asset <sums file> <asset name>
    _sums_file="$1"
    _asset="$2"

    if [ "$(wc -l < "$_sums_file" | tr -d ' ')" = "0" ] || ! grep -q ' ' "$_sums_file"; then
        # A bare "<digest>" file published next to a single asset.
        _bare="$(tr -d '[:space:]' < "$_sums_file")"
        case "$_bare" in
            [0-9a-fA-F]*) printf '%s' "$_bare" | tr '[:upper:]' '[:lower:]'; return 0 ;;
        esac
    fi

    _line="$(grep -E "[ *]$(printf '%s' "$_asset" | sed 's/[][\.*^$/]/\\&/g')\$" "$_sums_file" | head -n 1)"
    if [ -z "$_line" ]; then
        echo "no checksum entry for ${_asset}" >&2
        return 1
    fi
    printf '%s' "$_line" | awk '{print $1}' | tr '[:upper:]' '[:lower:]'
}

verify_checksum() {
    # verify_checksum <file> <expected digest>
    _actual="$(sha256_of "$1")"
    _expected="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
    if [ "$_actual" != "$_expected" ]; then
        echo "checksum mismatch for $1: expected $_expected, got $_actual" >&2
        return 1
    fi
    printf '%s' "$_actual"
}

# --- Installation -----------------------------------------------------------

extract_archive() {
    # extract_archive <archive> <dest dir>
    case "$1" in
        *.tar.gz|*.tgz)
            command -v tar >/dev/null 2>&1 || die "tar is required to unpack $1"
            tar -xzf "$1" -C "$2"
            ;;
        *.zip)
            command -v unzip >/dev/null 2>&1 || die "unzip is required to unpack $1"
            unzip -q "$1" -d "$2"
            ;;
        *) die "unsupported archive format: $1" ;;
    esac
}

install_from_dir() {
    # install_from_dir <dir> <binary name>
    _dir="$1"
    _binary="$2"
    _suffix=""
    [ "$OS" = "windows" ] && _suffix=".exe"

    _found="$(find "$_dir" -type f -name "${_binary}${_suffix}" | head -n 1)"
    if [ -z "$_found" ]; then
        die "archive does not contain ${_binary}${_suffix}"
    fi

    chmod +x "$_found"
    if [ -w "$PREFIX" ]; then
        mv "$_found" "${PREFIX}/${_binary}${_suffix}"
    else
        echo "  Installing to ${PREFIX} (requires sudo)..."
        sudo mv "$_found" "${PREFIX}/${_binary}${_suffix}"
    fi
    echo "  ✓ Installed ${_binary} to ${PREFIX}/${_binary}${_suffix}"
}

main() {
    case "${1:-}" in
        --help|-h) usage; exit 0 ;;
    esac
    if [ "$INSTALLER_RELEASES_AVAILABLE" -ne 1 ]; then
        usage >&2
        die "Prebuilt Streamline installation is unavailable; no files were downloaded or installed."
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            --version) VERSION="${2:?--version requires a value}"; shift 2 ;;
            --prefix)  PREFIX="${2:?--prefix requires a value}"; shift 2 ;;
            --repo)    REPO="${2:?--repo requires a value}"; shift 2 ;;
            --libc)    LIBC="${2:?--libc requires a value}"; shift 2 ;;
            --asset)   ASSET_OVERRIDE="${2:?--asset requires a value}"; shift 2 ;;
            --help|-h) usage; exit 0 ;;
            *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
        esac
    done

    echo ""
    echo "  ⚡ Streamline Installer"
    echo "  ─────────────────────────"
    echo ""

    case "$LIBC" in
        gnu|musl) ;;
        *) die "Unsupported --libc '$LIBC' (expected: gnu, musl)" ;;
    esac

    detect_platform
    if [ "$OS" = "linux" ]; then
        echo "  Platform: ${PLATFORM} (${LIBC})"
    else
        echo "  Platform: ${PLATFORM}"
    fi

    if [ -z "$VERSION" ] || [ "$VERSION" = "latest" ]; then
        echo "  Resolving the latest release..."
        VERSION="$(release_json latest | parse_tag_name || true)"
        if [ -z "$VERSION" ]; then
            die "Could not determine the latest release of ${REPO}. Re-run with --version X.Y.Z."
        fi
    fi

    echo "  Version:  ${VERSION}"
    echo "  Prefix:   ${PREFIX}"
    echo ""

    metadata="$(release_json "v${VERSION}" || true)"
    [ -n "$metadata" ] || die "Release v${VERSION} not found in ${REPO}"

    assets="$(printf '%s' "$metadata" | parse_asset_names)"
    [ -n "$assets" ] || die "Release v${VERSION} publishes no assets"

    if [ -n "$ASSET_OVERRIDE" ]; then
        archive="$ASSET_OVERRIDE"
        printf '%s\n' "$assets" | grep -Fxq "$archive" \
            || die "Asset ${archive} is not part of release v${VERSION}"
    else
        archive="$(printf '%s\n' "$assets" | select_asset "$OS" "$ARCH_ALTERNATIVES" "$LIBC")" \
            || die "Could not determine the release archive for ${PLATFORM}"
    fi

    sums_asset="$(printf '%s\n' "$assets" | select_checksum_asset "$archive")" \
        || die "Release v${VERSION} has no checksum file; refusing to install unverified binaries"

    workdir="$(mktemp -d)"
    # shellcheck disable=SC2064  # workdir must expand now, not at trap time
    trap "rm -rf '$workdir'" EXIT INT TERM

    base="https://github.com/${REPO}/releases/download/v${VERSION}"

    echo "  Downloading ${archive}..."
    http_download "${base}/${archive}" "${workdir}/${archive}" \
        || die "Failed to download ${archive}"
    [ -s "${workdir}/${archive}" ] || die "Downloaded ${archive} is empty"

    echo "  Downloading ${sums_asset}..."
    http_download "${base}/${sums_asset}" "${workdir}/${sums_asset}" \
        || die "Failed to download ${sums_asset}"

    expected="$(checksum_for_asset "${workdir}/${sums_asset}" "$archive")" \
        || die "No checksum published for ${archive}"

    digest="$(verify_checksum "${workdir}/${archive}" "$expected")" \
        || die "Checksum verification failed for ${archive}"
    echo "  ✓ Verified sha256:${digest}"

    mkdir -p "${workdir}/unpacked"
    extract_archive "${workdir}/${archive}" "${workdir}/unpacked"

    mkdir -p "$PREFIX" 2>/dev/null || sudo mkdir -p "$PREFIX"

    install_from_dir "${workdir}/unpacked" streamline
    install_from_dir "${workdir}/unpacked" streamline-cli

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

# Tests source this script to exercise the helpers above without installing.
if [ "${STREAMLINE_INSTALLER_LIB:-0}" = "1" ]; then
    # shellcheck disable=SC2317  # reached only when this file is sourced
    return 0 2>/dev/null || exit 0
fi

main "$@"
