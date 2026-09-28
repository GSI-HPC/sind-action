---
name: steward
description: Drive a sind-action pull request to a mergeable state. Covers local checks before pushing, testing script changes without Docker, updating the branch by rebasing onto main, and triaging the lint and e2e CI jobs. Use when opening, updating, or watching a PR in this repository.
---

# Steward a sind-action PR

## Before every push

1. `shellcheck scripts/*.sh` and `actionlint` are clean.
2. Script changes: run the script against a stub `sind` on `PATH`, using mikefarah
   `yq` v4 (`go install github.com/mikefarah/yq/v4@latest`), for every sind version
   branch the change touches. Example stub for `create.sh`:

   ```bash
   T=$(mktemp -d)
   cat > "$T/sind" <<'EOF'
   #!/usr/bin/env bash
   [[ "$1" == version ]] && { echo '{"version":"0.9.0"}'; exit 0; }
   echo "sind $*"
   EOF
   chmod +x "$T/sind"
   PATH="$T:$PATH" SIND_VERBOSITY=-v GITHUB_OUTPUT="$T/out" \
     SIND_CLUSTERS='- kind: Cluster
     name: c1
     nodes: [controller]' bash scripts/create.sh
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
