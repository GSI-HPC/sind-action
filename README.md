# sind-action

GitHub Action to install [sind](https://github.com/GSI-HPC/sind) and manage
Slurm-in-Docker clusters in CI.

## Usage

```yaml
jobs:
  slurm-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - uses: GSI-HPC/sind-action@v2
        with:
          clusters: |
            - test/cluster.yml

      - name: Run Slurm tests
        run: |
          sind exec -- sinfo
          sind exec -- srun hostname

      - uses: GSI-HPC/sind-action/cleanup@v2
        if: always()
```

## Requirements

- A Linux x64 or ARM64 runner, such as `ubuntu-latest` or `ubuntu-24.04-arm`.
  The action installs the sind binary for the runner's architecture. ARM64
  runners need sind v0.10.0 or later, the first release with linux/arm64
  binaries and node images.
- A rootful Docker daemon (not rootless or userns-remap) on unified cgroup v2,
  which `sind doctor` checks before any cluster is created.
- `bash`, `curl`, `jq` and [mikefarah `yq`](https://github.com/mikefarah/yq) v4.
- The [GitHub CLI](https://cli.github.com/) `gh` 2.93.0 or later, which
  verifies the sind binary's build provenance attestation (see
  [Binary verification](#binary-verification)).

GitHub's Ubuntu runners meet all of these.

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `version` | sind version to install (e.g. `v0.9.0`; minimum `v0.8.0`) | `latest` |
| `verify` | Verify the sind binary's build provenance attestation with `gh` (see below) | `true` |
| `token` | GitHub token for `gh` to read the attestations of the public sind repository | `github.token` |
| `clusters` | YAML list of cluster definitions (see below) | — |
| `pull` | Pull container images before creating | `true` |
| `wait` | How long `sind create cluster` waits for the nodes and Slurm, e.g. `10m`, or `0` for no limit (see below) | sind's default |
| `realm` | sind realm for resource isolation (a DNS label, see below) | — |

### Binary verification

The action downloads the sind binary into a temporary directory and installs
it only once it passes these checks, for sind v0.10.0 and later:

- Its sha256 checksum must match the release's `checksums.txt`, which catches a
  truncated or corrupted download.
- With `verify: true`, the default, its build provenance attestation must show
  that sind's release workflow (`.github/workflows/release.yml`) built it from
  the release tag on a GitHub-hosted runner. The action checks this with
  `gh attestation verify` and `token`; the default `github.token` needs no extra
  permissions to read the public sind repository's attestations. gh contacts
  `api.github.com` and Sigstore's trust roots (`tuf-repo-cdn.sigstore.dev`,
  `tuf-repo.github.com`), so runners with an egress allowlist must allow them.
  On GitHub Enterprise Server, pass a github.com token as `token`.

sind v0.9.0 and older publish neither, so the action installs them unverified
and says so in a notice. On runners without `gh`, such as some self-hosted ones,
set `verify: false` to keep only the checksum check.

### Cluster definitions

Each entry in `clusters` is either a **filepath** to a sind cluster config or
an **inline** cluster config. Each entry creates one cluster via
`sind create cluster --config <file>`, and the cluster's status is printed right
after it is created.

```yaml
clusters: |
  - test/cluster.yml
  - kind: Cluster
    name: dev
    nodes:
      - controller
      - worker: 3
```

### Wait limit

`wait` limits how long `sind create cluster` waits for each cluster to become
ready: for the node checks and the Slurm daemons and, for a cluster with
accounting, for its registration with slurmdbd. The limit counts from when the
node containers have started, so image pulls don't count. When it expires, sind
removes the partly created cluster again and the step fails. Leave `wait` empty
for sind's default, or set `0` for no limit.

```yaml
- uses: GSI-HPC/sind-action@v2
  with:
    wait: 10m
    clusters: |
      - test/cluster.yml
```

`sind create cluster --wait` needs a sind release after v0.10.0. With older
ones, the action ignores `wait` with a warning.

## Outputs

| Output | Description |
|--------|-------------|
| `clusters` | Comma-separated list of created cluster names |
| `version` | Installed sind version |

## Cleanup

Use the cleanup sub-action to tear down clusters after your tests:

```yaml
- uses: GSI-HPC/sind-action/cleanup@v2
  if: always()
```

This deletes all clusters (within the configured `realm`, if one is set).

## Parallel Jobs with Realm Isolation

Use `realm` to isolate clusters when running multiple jobs on the same runner.
A realm name must be a single DNS label: lowercase letters, digits and `-`, 1 to
63 characters, not beginning or ending with `-`. sind v0.10.0 and later reject
other names, such as `Unit`, `unit_tests` or `ubuntu-24.04`, so pick matrix values
that fit or map them to a valid name.

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        suite: [unit, integration, e2e]
    steps:
      - uses: actions/checkout@v7

      - uses: GSI-HPC/sind-action@v2
        with:
          realm: ${{ matrix.suite }}
          clusters: |
            - cluster.yml

      - run: make test-${{ matrix.suite }}

      - uses: GSI-HPC/sind-action/cleanup@v2
        if: always()
```

## Slurm Versions

Clusters whose config sets no `defaults.image` use sind's default node image:

- sind releases after v0.10.0 default to the image published for that release,
  `ghcr.io/gsi-hpc/sind-node:vX.Y.Z`, which carries the newest Slurm release
  line at the time of that release. Pinning `version` therefore also pins the
  Slurm version, and `version: latest` follows the newest sind release and its
  image.
- sind v0.10.0 and older default to `ghcr.io/gsi-hpc/sind-node:latest`.

sind also publishes an image per supported Slurm release line:

- `<YY>.<MM>` (e.g. `25.11`) moves: built from sind's `main`, it follows the
  newest Slurm release of that line.
- `vX.Y.Z-<YY>.<MM>` (e.g. `vX.Y.Z-25.11`) is fixed per sind release (after
  v0.10.0): its Slurm version stays the same.

With `pull: true`, the default, every run fetches the current image behind a
moving tag such as `latest` or `<YY>.<MM>`.

To test against several release lines, set the image in the cluster config:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        slurm: ['25.11', '26.05']
    steps:
      - uses: actions/checkout@v7

      - uses: GSI-HPC/sind-action@v2
        with:
          clusters: |
            - kind: Cluster
              name: dev
              defaults:
                image: ghcr.io/gsi-hpc/sind-node:${{ matrix.slurm }}
              nodes:
                - controller
                - worker: 2

      - run: sind exec dev -- srun -N2 hostname

      - uses: GSI-HPC/sind-action/cleanup@v2
        if: always()
```

The `<YY>.<MM>` tags move, so a later run may test a newer Slurm release of the
same line. For reproducible runs with a sind release after v0.10.0, pin
`version` and use that release's fixed tags:

```yaml
- uses: GSI-HPC/sind-action@v2
  with:
    version: vX.Y.Z
    clusters: |
      - kind: Cluster
        name: dev
        defaults:
          image: ghcr.io/gsi-hpc/sind-node:vX.Y.Z-${{ matrix.slurm }}
        nodes:
          - controller
          - worker: 2
```

See [Official images](https://gsi-hpc.github.io/sind/container-images/building-images/#official-images)
for the available tags.

## AI disclosure

This project is developed with the help of AI coding tools. Since September 2026,
changes written by Anthropic's Claude Code agent are committed as
`Claude <noreply@anthropic.com>` and/or carry a `Co-Authored-By: Claude …` trailer;
earlier AI-assisted commits are not individually marked.

---

Copyright (c) 2026 GSI Helmholtzzentrum fuer Schwerionenforschung GmbH.
Licensed under the [MIT License](LICENSE).
