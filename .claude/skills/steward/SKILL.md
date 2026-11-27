---
name: steward
description: Drive a sind-action pull request to a mergeable state. Covers local checks before pushing, testing script changes without Docker, updating the branch by rebasing onto main, and triaging the lint and e2e CI jobs. Use when opening, updating, or watching a PR in this repository.
---

# Steward a sind-action PR

## Before every push

1. `shellcheck -x scripts/*.sh tests/*.sh` and `actionlint` are clean.
2. `tests/create.sh` and `tests/install.sh` pass, using mikefarah `yq` v4
   (`go install github.com/mikefarah/yq/v4@latest`). They run the scripts against
   stubs of `sind`, `curl` and `gh`. For a script change, add or change a test for
   every sind version branch, input and error message that the change touches, for
   example in `tests/create.sh`:

   ```bash
   test_wait() {
     create INPUT_CLUSTERS='- cluster.yml' INPUT_WAIT=10m STUB_SIND_VERSION=0.11.0
     expect_status 0
     expect_calls <<'WANT'
   sind -v create cluster file --config cluster.yml --wait 10m --pull=false
     config: {"kind":"Cluster","name":"file"}
   sind -v get cluster file
   WANT
   }
   ```

3. Input, output or behaviour changes: update `README.md` (tables and examples) and
   `action.yml` descriptions together.
4. Re-read the diff: quoted variables, `set -euo pipefail` preserved, Conventional
   Commit messages.

## Updating the branch

Rebase onto `main`, never merge `main` in:
`git fetch origin main && git rebase origin/main`, rerun the checks, then
`git push --force-with-lease`.

## CI (`.github/workflows/ci.yml`)

- `lint`: shellcheck and actionlint.
- `test`: the script tests. A failure prints the test, what it expected and the
  output of the script.
- `e2e`: runs the action from the checkout (`uses: ./`) for the oldest supported sind
  and `latest`, and for `latest` on `ubuntu-24.04-arm`. It creates a file-based and an
  inline cluster in a realm, checks the outputs, runs `sinfo`/`srun`, and verifies
  cleanup. Read the "Setup sind" step log to confirm the post-create status printed a
  cluster table, not help text.
- A failure while downloading sind, or pulling the node image from ghcr.io, with a
  network error is upstream. Re-run once and report it if it repeats. Anything else is
  this PR's to fix. Never drop a matrix entry or a check to get green.

## GitHub etiquette

- Ask the maintainer before posting any comment or review reply, and never @-mention
  anyone.
- Never merge PRs, push to `main`, or create tags or releases.
