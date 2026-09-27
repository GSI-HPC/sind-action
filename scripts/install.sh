#!/usr/bin/env bash
set -euo pipefail

# sind releases Linux binaries for x86-64 and, after v0.9.0, arm64.
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) ARCH=amd64 ;;
  Linux/aarch64 | Linux/arm64) ARCH=arm64 ;;
  *)
    echo "::error::sind runs only on Linux x64 and ARM64 runners, not on $(uname -s) $(uname -m)"
    exit 1
    ;;
esac

REPO_URL="https://github.com/GSI-HPC/sind"
VERSION="${SIND_VERSION:-latest}"
CURL_OPTS=(--fail --silent --show-error --location --retry 3 --retry-connrefused)

# Resolve latest from the redirect of the latest release page. The GitHub API
# allows only 60 unauthenticated requests per hour per IP address.
if [[ "$VERSION" == "latest" ]]; then
  echo "Resolving latest sind version..."
  if ! latest_url=$(curl "${CURL_OPTS[@]}" --head --output /dev/null --write-out '%{url_effective}' "${REPO_URL}/releases/latest") ||
    [[ "$latest_url" != "${REPO_URL}/releases/tag/"* ]]; then
    echo "::error::Failed to resolve latest sind version"
    exit 1
  fi
  VERSION="${latest_url##*/}"
fi

# Release tags are vX.Y.Z; accept the version with or without the "v".
if [[ ! "$VERSION" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  echo "::error::Invalid sind version: ${VERSION} (expected e.g. v0.9.0 or latest)"
  exit 1
fi
VERSION="v${VERSION#v}"

MIN_VERSION="v0.8.0"
if [[ "$(printf '%s\n' "$MIN_VERSION" "$VERSION" | sort -V | head -n1)" != "$MIN_VERSION" ]]; then
  echo "::error::sind ${VERSION} is not supported, minimum required version is ${MIN_VERSION}"
  exit 1
fi

# v0.9.0 and earlier publish only sind-linux-amd64.
LAST_AMD64_ONLY="v0.9.0"
if [[ "$ARCH" == "arm64" && "$(printf '%s\n' "$LAST_AMD64_ONLY" "$VERSION" | sort -V | tail -n1)" == "$LAST_AMD64_ONLY" ]]; then
  echo "::error::sind ${VERSION} has no linux/arm64 binary; ARM64 runners need a sind release after ${LAST_AMD64_ONLY}"
  exit 1
fi

echo "Installing sind ${VERSION} (linux/${ARCH})..."

DOWNLOAD_URL="${REPO_URL}/releases/download/${VERSION}/sind-linux-${ARCH}"
INSTALL_DIR="${HOME}/.local/bin"
mkdir -p "$INSTALL_DIR"

if ! curl "${CURL_OPTS[@]}" --output "${INSTALL_DIR}/sind" "$DOWNLOAD_URL"; then
  echo "::error::Failed to download sind ${VERSION} from ${DOWNLOAD_URL}"
  exit 1
fi

chmod +x "${INSTALL_DIR}/sind"

# Make sind available in subsequent steps
echo "${INSTALL_DIR}" >> "$GITHUB_PATH"
export PATH="${INSTALL_DIR}:${PATH}"

# Verify
INSTALLED_VERSION=$("${INSTALL_DIR}/sind" version --json | jq -r '.version')
echo "Installed sind ${INSTALLED_VERSION}"

echo "version=${VERSION}" >> "$GITHUB_OUTPUT"
