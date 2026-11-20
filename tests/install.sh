#!/usr/bin/env bash
#
# Tests of scripts/install.sh without a network: stubs of uname, curl and gh
# on PATH serve the redirect of the latest release, the release assets and
# the result of the attestation check. The tests show which version and
# asset the script selects, what it verifies, and that it installs nothing
# that it did not verify.
#
# Usage: tests/install.sh [TEST...]

# shellcheck source-path=SCRIPTDIR
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

releases=https://github.com/GSI-HPC/sind/releases
identity=https://github.com/GSI-HPC/sind/.github/workflows/release.yml

setup() {
  stub uname <<'STUB'
#!/usr/bin/env bash
case "$1" in
  -s) echo "${STUB_OS:-Linux}" ;;
  -m) echo "${STUB_MACHINE:-x86_64}" ;;
esac
STUB

  # Serves ${STUB_LATEST} as the address that releases/latest redirects
  # to, the assets of assets/, and as checksums.txt ${STUB_CHECKSUMS}, or
  # the right checksums without it. A request for the asset that
  # ${STUB_MISSING} names, and for any other address, fails.
  stub curl <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
out=
url=
while (($#)); do
  case "$1" in
    --output)
      out=$2
      shift
      ;;
    --write-out | --retry) shift ;;
    -*) ;;
    *) url=$1 ;;
  esac
  shift
done
echo "curl $url" >> "$STUB_CALLS"
releases=https://github.com/GSI-HPC/sind/releases
asset=${url##*/}
case "$url" in
  "$releases/latest")
    [[ -n "${STUB_LATEST:-}" ]] || exit 22
    printf '%s' "$STUB_LATEST"
    ;;
  "$releases"/download/v*/*)
    [[ "$asset" != "${STUB_MISSING:-}" ]] || exit 22
    if [[ "$asset" != checksums.txt ]]; then
      cp "$STUB_ASSETS/$asset" "$out"
    elif [[ -n "${STUB_CHECKSUMS:-}" ]]; then
      printf '%s\n' "$STUB_CHECKSUMS" > "$out"
    else
      (cd "$STUB_ASSETS" && sha256sum sind-linux-*) > "$out"
    fi
    ;;
  *) exit 22 ;;
esac
STUB

  stub gh <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == --version ]]; then
  echo "gh version ${STUB_GH_VERSION:-2.93.0} (2026-01-01)"
  echo "https://github.com/cli/cli/releases/tag/v${STUB_GH_VERSION:-2.93.0}"
  exit 0
fi
echo "gh $*" >> "$STUB_CALLS"
exit "${STUB_GH_STATUS:-0}"
STUB

  # The release assets: each "binary" tells which one it is.
  mkdir assets
  local arch
  for arch in amd64 arm64; do
    printf '#!/usr/bin/env bash\necho "{\\"version\\":\\"stub-%s\\"}"\n' "$arch" > "assets/sind-linux-$arch"
  done

  # Only the stubs and the tools that the script needs are on PATH: a
  # command that the script must not have, such as the real curl or gh,
  # is not found.
  mkdir tools
  local tool
  for tool in bash env sort head tail sed awk cut mktemp rm mkdir install sha256sum jq cat cp; do
    ln -s "$(command -v "$tool")" "tools/$tool"
  done
}

# install_sind ASSIGNMENT...: runs install.sh with the given variables.
install_sind() {
  set +e
  env -i PATH="$PWD/stubs:$PWD/tools" HOME="$PWD/home" STUB_CALLS="$PWD/calls" STUB_ASSETS="$PWD/assets" \
    GITHUB_OUTPUT="$PWD/output" GITHUB_PATH="$PWD/path" "$@" \
    bash "$root/scripts/install.sh" > log 2>&1
  status=$?
  set -e
}

# expect_installed ARCH VERSION: sind is installed, from the asset of ARCH,
# and the outputs name VERSION.
expect_installed() {
  expect_status 0
  [[ -x home/.local/bin/sind ]] || fail "sind is not installed"
  cmp -s home/.local/bin/sind "assets/sind-linux-$1" || fail "the installed sind is not sind-linux-$1"
  expect_log "Installed sind stub-$1"
  expect_file output <<WANT
version=$2
WANT
  expect_file path <<WANT
$PWD/home/.local/bin
WANT
}

# expect_not_installed ERROR: the script failed with ERROR and left
# nothing.
expect_not_installed() {
  expect_status 1
  expect_log "::error::$1"
  [[ ! -e home/.local/bin/sind ]] || fail "sind is installed"
  expect_file output < /dev/null
  expect_file path < /dev/null
}

test_release_without_checksums() {
  install_sind SIND_VERSION=v0.8.0
  expect_installed amd64 v0.8.0
  expect_log "::notice::sind v0.8.0 has no checksums or attestations"
  expect_calls <<WANT
curl $releases/download/v0.8.0/sind-linux-amd64
WANT
}

test_last_release_without_checksums() {
  install_sind SIND_VERSION=v0.9.3
  expect_installed amd64 v0.9.3
  expect_calls <<WANT
curl $releases/download/v0.9.3/sind-linux-amd64
WANT
}

test_release_with_checksums_and_attestation() {
  install_sind SIND_VERSION=v0.10.0
  expect_installed amd64 v0.10.0
  expect_log "Checksum of sind-linux-amd64 matches checksums.txt"
  expect_calls <<WANT
curl $releases/download/v0.10.0/sind-linux-amd64
curl $releases/download/v0.10.0/checksums.txt
gh attestation verify TMP/sind-linux-amd64 --repo GSI-HPC/sind --cert-identity $identity@refs/tags/v0.10.0 --source-ref refs/tags/v0.10.0 --deny-self-hosted-runners
WANT
}

test_version_without_v() {
  install_sind SIND_VERSION=0.11.2
  expect_installed amd64 v0.11.2
  expect_calls <<WANT
curl $releases/download/v0.11.2/sind-linux-amd64
curl $releases/download/v0.11.2/checksums.txt
gh attestation verify TMP/sind-linux-amd64 --repo GSI-HPC/sind --cert-identity $identity@refs/tags/v0.11.2 --source-ref refs/tags/v0.11.2 --deny-self-hosted-runners
WANT
}

test_latest() {
  local version
  for version in "SIND_VERSION=latest" "UNSET="; do # the default is latest
    rm -rf calls output path home
    install_sind "$version" STUB_LATEST="$releases/tag/v0.12.0"
    expect_installed amd64 v0.12.0
    expect_calls <<WANT
curl $releases/latest
curl $releases/download/v0.12.0/sind-linux-amd64
curl $releases/download/v0.12.0/checksums.txt
gh attestation verify TMP/sind-linux-amd64 --repo GSI-HPC/sind --cert-identity $identity@refs/tags/v0.12.0 --source-ref refs/tags/v0.12.0 --deny-self-hosted-runners
WANT
  done
}

test_latest_does_not_resolve() {
  install_sind SIND_VERSION=latest
  expect_not_installed "Failed to resolve latest sind version"

  # A redirect to another page, such as a login page, names no release.
  install_sind SIND_VERSION=latest STUB_LATEST=https://github.com/login
  expect_not_installed "Failed to resolve latest sind version"
  install_sind SIND_VERSION=latest STUB_LATEST="$releases"
  expect_not_installed "Failed to resolve latest sind version"
  expect_calls <<WANT
curl $releases/latest
curl $releases/latest
curl $releases/latest
WANT
}

test_latest_that_is_no_version() {
  install_sind SIND_VERSION=latest STUB_LATEST="$releases/tag/nightly"
  expect_not_installed "Invalid sind version: nightly (expected e.g. v0.9.0 or latest)"
}

test_invalid_version() {
  local version
  for version in main v1 1.2 "" x0.9.0; do
    install_sind SIND_VERSION="$version"
    if [[ -z "$version" ]]; then
      # An empty version is the default: latest, which the stub does not resolve.
      expect_not_installed "Failed to resolve latest sind version"
    else
      expect_not_installed "Invalid sind version: $version (expected e.g. v0.9.0 or latest)"
    fi
  done
}

test_version_before_the_minimum() {
  local version
  for version in v0.7.9 0.1.0; do
    install_sind SIND_VERSION="$version"
    expect_not_installed "sind v${version#v} is not supported, minimum required version is v0.8.0"
  done
  expect_calls < /dev/null
}

test_arm64() {
  local machine
  for machine in aarch64 arm64; do
    rm -rf calls output path home
    install_sind SIND_VERSION=v0.10.0 STUB_MACHINE="$machine"
    expect_installed arm64 v0.10.0
    expect_calls <<WANT
curl $releases/download/v0.10.0/sind-linux-arm64
curl $releases/download/v0.10.0/checksums.txt
gh attestation verify TMP/sind-linux-arm64 --repo GSI-HPC/sind --cert-identity $identity@refs/tags/v0.10.0 --source-ref refs/tags/v0.10.0 --deny-self-hosted-runners
WANT
  done
}

test_arm64_needs_a_release_after_v0_9_0() {
  local version
  for version in v0.8.0 v0.9.0; do
    install_sind SIND_VERSION="$version" STUB_MACHINE=aarch64
    expect_not_installed "sind $version has no linux/arm64 binary; ARM64 runners need a sind release after v0.9.0"
  done
  expect_calls < /dev/null
}

test_other_platforms() {
  install_sind SIND_VERSION=v0.10.0 STUB_OS=Darwin STUB_MACHINE=arm64
  expect_not_installed "sind runs only on Linux x64 and ARM64 runners, not on Darwin arm64"
  install_sind SIND_VERSION=v0.10.0 STUB_MACHINE=riscv64
  expect_not_installed "sind runs only on Linux x64 and ARM64 runners, not on Linux riscv64"
  expect_calls < /dev/null
}

test_verify_must_be_true_or_false() {
  install_sind SIND_VERSION=v0.10.0 SIND_VERIFY=no
  expect_not_installed "verify must be true or false, got: no"
  expect_calls < /dev/null
}

# verify: false is for runners without gh. The checksum is still checked.
test_verify_false_needs_no_gh() {
  rm stubs/gh
  install_sind SIND_VERSION=v0.10.0 SIND_VERIFY=false
  expect_installed amd64 v0.10.0
  expect_log "Checksum of sind-linux-amd64 matches checksums.txt"
  expect_log "::notice::Skipping the attestation check of sind v0.10.0 (verify: false)"
  expect_calls <<WANT
curl $releases/download/v0.10.0/sind-linux-amd64
curl $releases/download/v0.10.0/checksums.txt
WANT
}

test_verify_false_with_gh_does_not_use_it() {
  install_sind SIND_VERSION=v0.10.0 SIND_VERIFY=false STUB_GH_STATUS=1 STUB_GH_VERSION=1.0.0
  expect_installed amd64 v0.10.0
}

# A release without attestations needs no gh, whatever verify says.
test_old_release_needs_no_gh() {
  rm stubs/gh
  install_sind SIND_VERSION=v0.9.0 SIND_VERIFY=true
  expect_installed amd64 v0.9.0
}

# The script downloads nothing when it cannot verify it.
test_gh_missing() {
  rm stubs/gh
  install_sind SIND_VERSION=v0.10.0
  expect_not_installed "Verifying the sind binary's attestation needs the GitHub CLI (gh) 2.93.0 or later; install it, or set the input verify: false to skip this check"
  expect_calls < /dev/null
}

test_gh_too_old() {
  local version
  for version in 2.92.9 2.9.0 1.14.0; do
    install_sind SIND_VERSION=v0.10.0 STUB_GH_VERSION="$version"
    expect_not_installed "Verifying the sind binary's attestation needs the GitHub CLI (gh) 2.93.0 or later, found $version;"
  done
  expect_calls < /dev/null
}

test_gh_version_unknown() {
  stub gh <<'STUB'
#!/usr/bin/env bash
echo "not the GitHub CLI"
STUB
  install_sind SIND_VERSION=v0.10.0
  expect_not_installed "Verifying the sind binary's attestation needs the GitHub CLI (gh) 2.93.0 or later, found an unknown version;"
}

test_gh_newer() {
  install_sind SIND_VERSION=v0.10.0 STUB_GH_VERSION=2.102.0
  expect_installed amd64 v0.10.0
}

test_binary_download_fails() {
  install_sind SIND_VERSION=v0.10.0 STUB_MISSING=sind-linux-amd64
  expect_not_installed "Failed to download sind v0.10.0 from $releases/download/v0.10.0/sind-linux-amd64"
}

test_checksums_download_fails() {
  install_sind SIND_VERSION=v0.10.0 STUB_MISSING=checksums.txt
  expect_not_installed "Failed to download the checksums of sind v0.10.0 from $releases/download/v0.10.0/checksums.txt"
  expect_calls <<WANT
curl $releases/download/v0.10.0/sind-linux-amd64
curl $releases/download/v0.10.0/checksums.txt
WANT
}

# A binary that is not the one of checksums.txt is not installed, with or
# without the attestation check, and gh does not see it.
test_checksum_mismatch() {
  local zeros verify
  zeros=$(printf '0%.0s' {1..64})
  for verify in true false; do
    rm -f calls
    install_sind SIND_VERSION=v0.10.0 SIND_VERIFY="$verify" STUB_CHECKSUMS="$zeros  sind-linux-amd64"
    expect_not_installed "Checksum mismatch for sind-linux-amd64 of sind v0.10.0: expected $zeros, got $(sha256sum assets/sind-linux-amd64 | cut -d ' ' -f 1); sind was not installed"
    expect_calls <<WANT
curl $releases/download/v0.10.0/sind-linux-amd64
curl $releases/download/v0.10.0/checksums.txt
WANT
  done
}

# The checksum of the other asset does not count.
test_checksum_of_the_asset_of_the_runner() {
  local amd64 arm64
  amd64=$(sha256sum assets/sind-linux-amd64 | cut -d ' ' -f 1)
  arm64=$(sha256sum assets/sind-linux-arm64 | cut -d ' ' -f 1)
  install_sind SIND_VERSION=v0.10.0 STUB_CHECKSUMS="$arm64  sind-linux-amd64
$amd64  sind-linux-arm64"
  expect_not_installed "Checksum mismatch for sind-linux-amd64"
}

test_checksums_without_one_checksum_for_the_asset() {
  local sum checksums
  sum=$(sha256sum assets/sind-linux-amd64 | cut -d ' ' -f 1)
  for checksums in \
    "$sum  sind-linux-arm64" \
    "$sum  sind-linux-amd64"$'\n'"$sum  sind-linux-amd64" \
    "${sum:0:40}  sind-linux-amd64" \
    "${sum^^}  sind-linux-amd64" \
    "<html>Not Found</html>"; do
    install_sind SIND_VERSION=v0.10.0 STUB_CHECKSUMS="$checksums"
    expect_not_installed "checksums.txt of sind v0.10.0 has no single sha256 checksum for sind-linux-amd64"
  done
}

test_attestation_check_fails() {
  install_sind SIND_VERSION=v0.10.0 STUB_GH_STATUS=1
  expect_not_installed "Failed to verify the build provenance attestation of sind-linux-amd64 of sind v0.10.0; sind was not installed"
}

run_tests "$@"
