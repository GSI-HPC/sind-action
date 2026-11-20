#!/usr/bin/env bash
#
# Tests of scripts/create.sh with a stub sind on PATH: which sind commands
# the script runs for each form of the clusters input, for each input and
# for each sind release that changes them, and what it writes to the
# clusters output. They need jq and mikefarah yq v4, as the script does.
#
# Usage: tests/create.sh [TEST...]

# shellcheck source-path=SCRIPTDIR
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

setup() {
  # Records each command, and for a create the config it would read.
  stub sind <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == "version --json" ]]; then
  echo "{\"version\":\"${STUB_SIND_VERSION}\"}"
  exit 0
fi
echo "sind $*" >> "$STUB_CALLS"
if [[ "$2 $3" == "create cluster" ]]; then
  name=$4
  while (($#)); do
    if [[ "$1" == --config ]]; then
      echo "  config: $(yq -o=json -I=0 '.' "$2")" >> "$STUB_CALLS"
    fi
    shift
  done
  [[ "$name" != "${STUB_CREATE_FAILS:-}" ]]
fi
STUB
  printf 'kind: Cluster\nname: file\n' > cluster.yml
  printf 'kind: Cluster\n' > unnamed.yml
}

# create ASSIGNMENT...: runs create.sh with the stub sind of the given
# release (default: one that has every feature) and the given inputs.
create() {
  set +e
  env PATH="$PWD/stubs:$PATH" STUB_CALLS="$PWD/calls" STUB_SIND_VERSION=1.0.0 \
    GITHUB_OUTPUT="$PWD/output" SIND_VERBOSITY=-v "$@" \
    bash "$root/scripts/create.sh" > log 2>&1
  status=$?
  set -e
}

test_file_and_inline_entries() {
  create INPUT_CLUSTERS='- cluster.yml
- kind: Cluster
  name: inline
  nodes:
    - controller
    - worker: 2'
  expect_status 0
  expect_calls <<'WANT'
sind -v create cluster file --config cluster.yml --pull=false
  config: {"kind":"Cluster","name":"file"}
sind -v get cluster file
sind -v create cluster inline --config TMP/inline-1.yml --pull=false
  config: {"kind":"Cluster","name":"inline","nodes":["controller",{"worker":2}]}
sind -v get cluster inline
WANT
  expect_file output <<'WANT'
clusters=file,inline
WANT
}

test_config_without_name_is_default() {
  create INPUT_CLUSTERS='- unnamed.yml'
  expect_status 0
  expect_calls <<'WANT'
sind -v create cluster default --config unnamed.yml --pull=false
  config: {"kind":"Cluster"}
sind -v get cluster default
WANT
  expect_file output <<'WANT'
clusters=default
WANT

  rm calls output
  create INPUT_CLUSTERS='- kind: Cluster
  nodes: [controller]'
  expect_status 0
  expect_calls <<'WANT'
sind -v create cluster default --config TMP/inline-0.yml --pull=false
  config: {"kind":"Cluster","nodes":["controller"]}
sind -v get cluster default
WANT
  expect_file output <<'WANT'
clusters=default
WANT
}

test_pull() {
  create INPUT_CLUSTERS='- cluster.yml' INPUT_PULL=true
  expect_status 0
  expect_calls <<'WANT'
sind -v create cluster file --config cluster.yml --pull
  config: {"kind":"Cluster","name":"file"}
sind -v get cluster file
WANT
}

# Only "true" pulls: sind must not fall back to its own default or to the
# SIND_PULL of the job.
test_pull_is_explicit() {
  local pull
  for pull in false "" yes; do
    rm -f calls
    create INPUT_CLUSTERS='- cluster.yml' INPUT_PULL="$pull" SIND_PULL=true
    expect_status 0
    expect_calls <<'WANT'
sind -v create cluster file --config cluster.yml --pull=false
  config: {"kind":"Cluster","name":"file"}
sind -v get cluster file
WANT
  done
}

test_wait() {
  create INPUT_CLUSTERS='- cluster.yml' INPUT_WAIT=10m INPUT_PULL=true
  expect_status 0
  expect_no_log "::warning::"
  expect_calls <<'WANT'
sind -v create cluster file --config cluster.yml --wait 10m --pull
  config: {"kind":"Cluster","name":"file"}
sind -v get cluster file
WANT
}

test_wait_with_first_release_that_has_it() {
  create INPUT_CLUSTERS='- cluster.yml' INPUT_WAIT=0 STUB_SIND_VERSION=0.10.1
  expect_status 0
  expect_no_log "::warning::"
  expect_calls <<'WANT'
sind -v create cluster file --config cluster.yml --wait 0 --pull=false
  config: {"kind":"Cluster","name":"file"}
sind -v get cluster file
WANT
}

test_wait_is_ignored_with_a_warning_up_to_v0_10_0() {
  local version
  for version in 0.8.0 0.10.0; do
    rm -f calls
    create INPUT_CLUSTERS='- cluster.yml' INPUT_WAIT=10m STUB_SIND_VERSION="$version"
    expect_status 0
    expect_log "::warning::The wait input needs a sind release after v0.10.0 and is ignored with sind $version"
    grep -q -- --wait calls && fail "sind $version got --wait"
  done
  return 0
}

test_no_warning_without_wait() {
  create INPUT_CLUSTERS='- cluster.yml' INPUT_WAIT= STUB_SIND_VERSION=0.8.0
  expect_status 0
  expect_no_log "::warning::"
}

test_status_before_v0_9_0() {
  create INPUT_CLUSTERS='- cluster.yml' STUB_SIND_VERSION=0.8.5
  expect_status 0
  expect_calls <<'WANT'
sind -v create cluster file --config cluster.yml --pull=false
  config: {"kind":"Cluster","name":"file"}
sind -v status file
WANT
}

test_get_cluster_from_v0_9_0() {
  local version
  for version in 0.9.0 0.10.0 0.11.2; do
    rm -f calls
    create INPUT_CLUSTERS='- cluster.yml' STUB_SIND_VERSION="$version"
    expect_status 0
    expect_calls <<'WANT'
sind -v create cluster file --config cluster.yml --pull=false
  config: {"kind":"Cluster","name":"file"}
sind -v get cluster file
WANT
  done
}

test_verbosity() {
  create INPUT_CLUSTERS='- cluster.yml' SIND_VERBOSITY=-vvv
  expect_status 0
  expect_calls <<'WANT'
sind -vvv create cluster file --config cluster.yml --pull=false
  config: {"kind":"Cluster","name":"file"}
sind -vvv get cluster file
WANT
}

test_empty_input_creates_nothing() {
  create INPUT_CLUSTERS=
  expect_status 0
  expect_calls < /dev/null
  expect_file output <<'WANT'
clusters=
WANT
}

test_input_that_is_no_list() {
  create INPUT_CLUSTERS='kind: Cluster
name: dev'
  expect_status 1
  expect_log "::error::clusters must be a YAML list, with one '- ' entry per cluster (got a map)"
  expect_calls < /dev/null
  expect_file output < /dev/null

  create INPUT_CLUSTERS='cluster.yml'
  expect_status 1
  expect_log "(got a scalar)"
  expect_calls < /dev/null
}

test_config_file_not_found() {
  create INPUT_CLUSTERS='- cluster.yml
- missing.yml'
  expect_status 1
  expect_log "::error::Config file not found: missing.yml"
  expect_calls <<'WANT'
sind -v create cluster file --config cluster.yml --pull=false
  config: {"kind":"Cluster","name":"file"}
sind -v get cluster file
WANT
  expect_file output < /dev/null
}

test_entry_that_is_a_list() {
  create INPUT_CLUSTERS='- [a, b]'
  expect_status 1
  expect_log "::error::Unexpected entry type at index 0: seq"
  expect_calls < /dev/null
}

test_config_that_is_no_yaml() {
  printf 'name: [\n' > broken.yml
  create INPUT_CLUSTERS='- broken.yml'
  expect_status 1
  expect_log "::error::Failed to read the cluster name from broken.yml"
  expect_calls < /dev/null
}

# The script stops at the first cluster that sind does not create, shows
# no status of it, and writes no output.
test_create_fails() {
  create INPUT_CLUSTERS='- cluster.yml
- kind: Cluster
  name: second
- kind: Cluster
  name: third' STUB_CREATE_FAILS=second
  expect_status 1
  expect_log "::error::Failed to create cluster from inline cluster 1"
  expect_calls <<'WANT'
sind -v create cluster file --config cluster.yml --pull=false
  config: {"kind":"Cluster","name":"file"}
sind -v get cluster file
sind -v create cluster second --config TMP/inline-1.yml --pull=false
  config: {"kind":"Cluster","name":"second"}
WANT
  expect_file output < /dev/null
}

# Some runner images have the Python yq wrapper, with another syntax.
test_other_yq_is_rejected() {
  stub yq <<'STUB'
#!/usr/bin/env bash
echo "yq 3.4.3"
STUB
  create INPUT_CLUSTERS='- cluster.yml'
  expect_status 1
  expect_log "::error::mikefarah yq v4 (https://github.com/mikefarah/yq) is required, found: yq 3.4.3"
  expect_calls < /dev/null
}

run_tests "$@"
