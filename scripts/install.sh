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

REPO="GSI-HPC/sind"
REPO_URL="https://github.com/${REPO}"
VERSION="${SIND_VERSION:-latest}"
VERIFY="${SIND_VERIFY:-true}"
CURL_OPTS=(--fail --silent --show-error --location --retry 3 --retry-connrefused)

if [[ "$VERIFY" != "true" && "$VERIFY" != "false" ]]; then
  echo "::error::verify must be true or false, got: ${VERIFY}"
  exit 1
fi

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

# v0.10.0 and later publish checksums.txt and a build provenance attestation
# for each binary; older releases have neither.
FIRST_ATTESTED="v0.10.0"
attested=false
if [[ "$(printf '%s\n' "$FIRST_ATTESTED" "$VERSION" | sort -V | head -n1)" == "$FIRST_ATTESTED" ]]; then
  attested=true
fi

if [[ "$attested" == "true" && "$VERIFY" == "true" ]] && ! command -v gh >/dev/null; then
  echo "::error::Verifying the sind binary's attestation needs the GitHub CLI (gh); install it, or set the input verify: false to skip this check"
  exit 1
fi

echo "Installing sind ${VERSION} (linux/${ARCH})..."

ASSET="sind-linux-${ARCH}"
DOWNLOAD_URL="${REPO_URL}/releases/download/${VERSION}"

# Download and verify in a temporary directory; only a verified binary is
# installed or run.
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
binary="${tmp_dir}/${ASSET}"

if ! curl "${CURL_OPTS[@]}" --output "$binary" "${DOWNLOAD_URL}/${ASSET}"; then
  echo "::error::Failed to download sind ${VERSION} from ${DOWNLOAD_URL}/${ASSET}"
  exit 1
fi

if [[ "$attested" == "true" ]]; then
  # The checksum catches a truncated or corrupted download.
  if ! curl "${CURL_OPTS[@]}" --output "${tmp_dir}/checksums.txt" "${DOWNLOAD_URL}/checksums.txt"; then
    echo "::error::Failed to download the checksums of sind ${VERSION} from ${DOWNLOAD_URL}/checksums.txt"
    exit 1
  fi
  expected=$(awk -v name="$ASSET" '$2 == name { print $1 }' "${tmp_dir}/checksums.txt")
  if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
    echo "::error::checksums.txt of sind ${VERSION} has no single sha256 checksum for ${ASSET}"
    exit 1
  fi
  actual=$(sha256sum "$binary" | cut -d ' ' -f 1)
  if [[ "$actual" != "$expected" ]]; then
    echo "::error::Checksum mismatch for ${ASSET} of sind ${VERSION}: expected ${expected}, got ${actual}; sind was not installed"
    exit 1
  fi
  echo "Checksum of ${ASSET} matches checksums.txt"

  # The attestation proves that sind's release workflow built the binary
  # from the release tag, on a GitHub-hosted runner.
  if [[ "$VERIFY" == "true" ]]; then
    echo "Verifying the build provenance attestation of ${ASSET}..."
    if ! gh attestation verify "$binary" --repo "$REPO" \
      --signer-workflow "${REPO}/.github/workflows/release.yml" \
      --source-ref "refs/tags/${VERSION}" --deny-self-hosted-runners; then
      echo "::error::Failed to verify the build provenance attestation of ${ASSET} of sind ${VERSION}; sind was not installed"
      exit 1
    fi
  else
    echo "::notice::Skipping the attestation check of sind ${VERSION} (verify: false)"
  fi
else
  echo "::notice::sind ${VERSION} has no checksums or attestations (sind ${FIRST_ATTESTED} and later have them); installing it unverified"
fi

INSTALL_DIR="${HOME}/.local/bin"
mkdir -p "$INSTALL_DIR"
install -m 755 "$binary" "${INSTALL_DIR}/sind"

# Make sind available in subsequent steps
echo "${INSTALL_DIR}" >> "$GITHUB_PATH"
export PATH="${INSTALL_DIR}:${PATH}"

# Verify
INSTALLED_VERSION=$("${INSTALL_DIR}/sind" version --json | jq -r '.version')
echo "Installed sind ${INSTALLED_VERSION}"

echo "version=${VERSION}" >> "$GITHUB_OUTPUT"
