#!/usr/bin/env bash
set -euo pipefail

VERSION="${SIND_VERSION:-latest}"

# Resolve latest version from GitHub releases
if [[ "$VERSION" == "latest" ]]; then
  echo "Resolving latest sind version..."
  VERSION=$(curl -fsSL "https://api.github.com/repos/GSI-HPC/sind/releases/latest" | jq -r '.tag_name')
  if [[ -z "$VERSION" || "$VERSION" == "null" ]]; then
    echo "::error::Failed to resolve latest sind version"
    exit 1
  fi
fi

echo "Installing sind ${VERSION}..."

DOWNLOAD_URL="https://github.com/GSI-HPC/sind/releases/download/${VERSION}/sind-linux-amd64"
INSTALL_DIR="${HOME}/.local/bin"
mkdir -p "$INSTALL_DIR"

if ! curl -fsSL "$DOWNLOAD_URL" -o "${INSTALL_DIR}/sind"; then
  echo "::error::Failed to download sind ${VERSION} from ${DOWNLOAD_URL}"
  exit 1
fi

chmod +x "${INSTALL_DIR}/sind"

# Make sind available in subsequent steps
echo "${INSTALL_DIR}" >> "$GITHUB_PATH"
export PATH="${INSTALL_DIR}:${PATH}"

# Verify
INSTALLED_VERSION=$("${INSTALL_DIR}/sind" --version)
echo "Installed sind ${INSTALLED_VERSION}"

echo "version=${VERSION}" >> "$GITHUB_OUTPUT"
