#!/usr/bin/env bash
set -euo pipefail

# sind releases only a Linux x86-64 binary.
if [[ "$(uname -s)/$(uname -m)" != "Linux/x86_64" ]]; then
  echo "::error::sind runs only on Linux x64 runners, not on $(uname -s) $(uname -m)"
  exit 1
fi

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

echo "Installing sind ${VERSION}..."

DOWNLOAD_URL="${REPO_URL}/releases/download/${VERSION}/sind-linux-amd64"
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
