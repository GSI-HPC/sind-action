#!/usr/bin/env bash
set -euo pipefail

VERSION="${SIND_VERSION:-latest}"

MAX_VERSION="v0.8.0"

# Resolve latest compatible version from GitHub releases
if [[ "$VERSION" == "latest" ]]; then
  echo "Resolving latest compatible sind version..."
  VERSION=$(curl -fsSL "https://api.github.com/repos/GSI-HPC/sind/releases" \
    | jq -r --arg max "$MAX_VERSION" '[.[].tag_name | select(. < $max)] | sort_by(split(".") | map(ltrimstr("v") | tonumber)) | last')
  if [[ -z "$VERSION" || "$VERSION" == "null" ]]; then
    echo "::error::Failed to resolve latest compatible sind version"
    exit 1
  fi
  echo "::warning::sind-action v1 supports sind < ${MAX_VERSION}. Please upgrade to sind-action v2 for newer sind releases."
elif [[ "$(printf '%s\n' "$MAX_VERSION" "$VERSION" | sort -V | head -n1)" == "$MAX_VERSION" ]]; then
  echo "::error::sind ${VERSION} is not supported by sind-action v1 (requires < ${MAX_VERSION}). Please upgrade to sind-action v2."
  exit 1
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
