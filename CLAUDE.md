# CLAUDE.md

sind-action is a composite GitHub Action that installs
[sind](https://github.com/GSI-HPC/sind) (Slurm in Docker) and creates clusters for CI
jobs. Personal, uncommitted instructions belong in `CLAUDE.local.md` (gitignored).

## Layout

- `action.yml`: install (`scripts/install.sh`), then set `SIND_VERBOSITY` (`-v`, or
  `-vvv` under `RUNNER_DEBUG`), run `sind doctor`, export `SIND_REALM` from the `realm`
  input, and create clusters (`scripts/create.sh`). Outputs: `clusters`, `version`.
- `scripts/install.sh`: resolves `latest` via the GitHub API, enforces `MIN_VERSION`,
  downloads `sind-linux-amd64` into `~/.local/bin`, and checks `sind version --json`.
- `scripts/create.sh`: each `clusters` entry is a config file path (scalar) or an inline
  config (map). It creates each cluster, prints its status, and writes the `clusters`
  output.
- `cleanup/action.yml`: `sind delete cluster --all` (in `SIND_REALM`, if set).
- `.github/workflows/ci.yml`: `lint` (shellcheck, actionlint) and `e2e`, which runs the
  action from the checkout against the oldest supported sind release and `latest`.

## Checks

```bash
shellcheck scripts/*.sh   # pip install shellcheck-py if missing
actionlint                # go install github.com/rhysd/actionlint/cmd/actionlint@latest
```

- Scripts run on GitHub's Ubuntu runners with bash, curl, jq and mikefarah `yq` v4.
  Some images ship the Python `yq` wrapper instead, which has different syntax. Test
  locally with the Go one.
- Cloud sessions have no Docker daemon. Test script logic against a stub `sind` on
  `PATH`; the `e2e` CI job is the real end-to-end run.

## sind compatibility

- The action supports sind >= `MIN_VERSION` (`scripts/install.sh`). Keep the `e2e`
  matrix on `MIN_VERSION` and `latest`.
- When the sind CLI changes (e.g. `sind status` became `sind get cluster` in v0.9.0),
  select the command from `sind version --json` instead of raising `MIN_VERSION`.
  Raising `MIN_VERSION` or breaking an input or output is a new major version.
- Inputs and outputs documented in `README.md` must match `action.yml`, and README
  examples use the current major tag.

## Branches, releases and commits

- PRs target `main`. Update a feature branch by rebasing it onto `main` (never merge
  `main` in), then `git push --force-with-lease`.
- Releases are `vX.Y.Z` tags plus a moving major tag (e.g. `v2`), created by the
  maintainer. Never push to `main`, create tags or releases, or merge PRs.
- Ask the maintainer before commenting on issues or PRs, and never @-mention anyone.
- Conventional Commits (`feat:`, `fix:`, `docs:`, `ci:`, `build:`), one logical change
  per commit, bullet-list bodies without development narrative.
- Commits by Claude Code are authored as `Claude <noreply@anthropic.com>` and carry a
  `Co-Authored-By: Claude …` trailer. Keep both; the README AI disclosure relies on them.
- `.claude/skills/steward` has the PR/CI routine.
