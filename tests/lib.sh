# shellcheck shell=bash
#
# Helpers for the script tests. A test file sources this file, defines a
# function setup and functions test_*, and calls run_tests as its last
# command. run_tests runs each test in a directory and a subshell of its
# own, so that no test sees the files or the variables of another one, and
# fails if a test fails.

set -euo pipefail

# The root of the repository.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export root

# The exit status of the script, which the function of a test file that
# runs the script sets.
status=0

# fail MESSAGE...: fails the test and shows the output of the script.
fail() {
  echo "  $*"
  if [[ -s log ]]; then
    echo "  output of the script:"
    sed 's/^/    /' log
  fi
  exit 1
}

# stub NAME: makes stubs/NAME from stdin, a command for PATH.
stub() {
  mkdir -p stubs
  cat > "stubs/$1"
  chmod +x "stubs/$1"
}

# expect_status WANT: the exit status of the script.
expect_status() {
  [[ "$status" == "$1" ]] || fail "exit status: want $1, got $status"
}

# expect_log TEXT: the output of the script contains TEXT.
expect_log() {
  grep -qF -- "$1" log || fail "no output: $1"
}

# expect_no_log TEXT: the output of the script does not contain TEXT.
expect_no_log() {
  ! grep -qF -- "$1" log || fail "unexpected output: $1"
}

# expect_calls: the commands that the script ran, in order, are those of
# stdin. The path of a temporary directory shows as TMP.
expect_calls() {
  touch calls
  diff -u --label want --label got - <(sed -E 's#/[^ ]*/tmp\.[^/ ]+/#TMP/#g' calls) ||
    fail "the script ran other commands"
}

# expect_file FILE: FILE has the content of stdin.
expect_file() {
  touch "$1"
  diff -u --label want --label "$1" - "$1" || fail "$1 has other content"
}

# run_tests: runs the tests of the file, or only those named as arguments.
run_tests() {
  local tests test failed=0
  work=$(mktemp -d) # global: the trap runs after the function
  trap 'rm -rf "$work"' EXIT
  if (($#)); then
    tests=("$@")
  else
    mapfile -t tests < <(declare -F | sed -n 's/^declare -f \(test_.*\)$/\1/p')
  fi
  for test in "${tests[@]}"; do
    mkdir "$work/$test"
    set +e
    (
      set -e
      cd "$work/$test"
      setup
      "$test"
    ) > "$work/$test.out" 2>&1
    local result=$?
    set -e
    if ((result == 0)); then
      echo "ok      $test"
    else
      echo "FAILED  $test"
      cat "$work/$test.out"
      failed=$((failed + 1))
    fi
  done
  echo "${#tests[@]} tests, $failed failed"
  ((failed == 0))
}
